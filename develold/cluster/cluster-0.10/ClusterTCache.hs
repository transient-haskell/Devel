{-# OPTIONS  -fglasgow-exts -fallow-undecidable-instances  #-}
module ClusterTCache where
import Transaction
import Cluster
import URIHold
import ProtocolHTTP
import qualified Data.TCache as T
import Data.Maybe(isJust,fromJust,mapMaybe)
import Control.Exception(handle, finally)
import Data.List (sortBy,nubBy,dropWhile)
import Data.HashTable(hashString)

import System.IO.Unsafe
import Control.Concurrent.STM 
import GHC.Conc	(unsafeIOToSTM)
import Control.Concurrent.MVar
import Control.Concurrent
import qualified Data.Map as M
import Data.List(partition,nub,find,(\\))
import System.Time
import Control.Exception(assert)
import Control.Monad(when)


getTVars :: T.IResource (Data1 op a)=> [Data1 op a] -> IO [Maybe (TVar (Data1 op a))] 
getTVars= T.getTVars

getTVarsIO :: T.IResource (Data1 op a)=> [Data1 op a] -> IO [TVar (Data1 op a)] 
getTVarsIO= T.getTVarsIO


getResource :: T.IResource (Data1 op a)=> Data1 op a ->IO (Maybe (Data1 op a))
getResource= T.getResource

getResources :: T.IResource (Data1 op a)=> [Data1 op a] ->IO [Maybe (Data1 op a)]
getResources= T.getResources

withResources ::(T.IResource (Data1 op a))=> [Data1 op a]->([Maybe (Data1 op a)]->[Data1 op a])->IO ()
withResources= T.withResources

withResource :: (T.IResource (Data1 op a))=> Data1 op a->(Maybe (Data1 op a)->Data1 op a)->IO ()
withResource= T.withResource

insertResources:: T.IResource (Data1 op a) =>[Data1 op a] -> IO ()
insertResources rs= T.withResources [] (\_->rs)

cleanTimes= 100  -- every 100 transactions the AllObjects list in memory will remove duplicate keys

type ObjectKeys= String

data Tr op=  Tr Id [ObjectKeys] op deriving (Read, Show, Eq)

data Op op a= Noop | AddObjects [Data1 op a] | Connect  |  Op op  deriving (Read, Show, Eq)

data State= Inactive 
          | ConnectReceived Int Id 
          | ConnectSent 
          | ToSendAddObjects Id 
          | ToSendConnect
          | Active
          deriving(Read,Show,Eq)

data Nod= Nod{uri:: URIHold, nodesConected::[NodeName]
                  , lastReceived::Id, consolidatedId:: Id
                  , active:: State} deriving(Read,Show,Eq)

nod0= Nod (makeURI "http://localhost") [] id0 id0 Inactive

data Data1 op a = MyNode Nod
                | Node Nod
                | AllObjects Int [(String,Integer)]
                | PendingTrans [Tr(Op op a)] 
                | Data1 a 
                deriving (Read, Show, Eq)

instance (Show op, Show a, Read op, Read a,T.IResource a) => T.IResource (Data1 op a )  where 
   keyResource (Node Nod{uri=URIHold s _})    = show $ hashString s
   keyResource (MyNode _)       = "MyNode"
   keyResource (PendingTrans _) = "PendingTrans"
   keyResource (AllObjects _ _ )= "AllObjects"
   keyResource (Data1 a)        = T.keyResource a

   serialize x   = show x              
   deserialize x = read x
   defPath _ = show s++"/" where 
                           url= unsafePerformIO $ readMVar myNodeName
                           s  = uriPort1 $ makeURI url 

instance (Read op, Show op,Read a, Show a) => T.IResource (Op op a) where
    serialize x= show x
    deserialize str= read str
    keyResource _= error "not defined key for Op"

class GetProto  a where
     getProto  :: String -> a
instance (GetProto  a) => GetProto  (Data1 op a) where
        getProto s@('h':'t':'t':'p':':':str) = Node nod0{uri=URIHold s undefined }
        getProto  "PendingTrans"   = PendingTrans undefined 
        getProto  "AllObjects"     = AllObjects undefined undefined
        getProto  str              = Data1 $ getProto  str
     



-- the mapping associate a transformation of objects from the operation codes received
class (Eq op, Eq a)=> TransMap op a | op ->a, a ->op  where
  mapping :: op -> ([Maybe a]-> [a])
  commutativeOp :: op -> Bool
  commutativeOp op= True

instance TransMap op a => TransMap  (Op op a) (Data1 op a)  where

  mapping Connect  = \_->[  ]
  mapping Noop = \_ ->[]
  
  mapping (AddObjects as) = \_ ->   as                                 `debug` "applying AddObjects"


  mapping (Op op) = f $ mapping op where          
          f f1 dmas =  map (\a-> Data1 a) as where
                 as= f1 mas  
                 mas= map filter dmas 
                 filter (Just (Data1 a))= Just a 
                 filter Nothing = Nothing

instance  TransMap  op a => Trans (Tr (Op op a)) (Data1 op a) Id where
  --apply:: t -> [Maybe a] -> IO [a]
  apply (Tr _ _ op) mas = (mapping op) mas                                                                        `debug` "apply"

  --getId:: t -> id
  getId (Tr id _ _)= id


  commutative (Tr _ _ (Connect )) = False
  commutative (Tr _ _ Noop) = True
  commutative (Tr _ _ (AddObjects _ )) = False

  commutative (Tr _ _ (Op op)) = commutativeOp op

  nullTrans= undefined
  allTransactions=undefined
  applyTo _= undefined 

  
instance TransMap op a => NTrans (Tr (Op op a)) (Data1 op a)  where
  --getNode :: t -> Int
  getNode t= node where Id _ _  node= getId t



instance (T.IResource op, TransMap (Op op a) (Data1 op a), GetProto  (Data1 op a),
          T.IResource  (Data1 op a),
          Trans (Tr(Op op a)) (Data1 op a) Id)  
          => SyncRepository (Tr (Op op a)) (Data1 op a) Id  
   where

   addTrans t= do
        id <- genIdNode 
        withResource (PendingTrans undefined) doit where
             doit (Just (PendingTrans ts :: Data1 op a)) =  PendingTrans (t:ts)
             doit Nothing= PendingTrans [t]


   emptyTranss= do
             id <- genIdNode                                             `debug` "emptyTranss getNode"               
             return $ Tr id []  Noop                                     `debug` "emptyTranss return"          

   
   applyTrans ts= mapM_ apply1 ts  where 
        apply1 t@(Tr _ keys op)=
           withResources ( AllObjects undefined undefined
                         : map (getProto  :: String -> (Data1 op a)) keys) (apply2 t) 

        apply2 t (allobjects:objs)=(AllObjects n xs):outobjs             `debug` ("**applyTrans*** "++concatMap T.serialize outobjs)

           where
           -- XXX clean AllObjects every N steps
           (n,xs)= case allobjects of
                 Nothing ->(0,keys1)
                 Just (AllObjects n' xs') ->if n' `mod` cleanTimes ==0 then  (nn,nubBy nubBy1 l) else (nn,l) where l= keys1++xs';nn= n'+ length keys1
           
           keys1= map keyt outobjs  where 
                keyt r= (T.keyResource r,time 0)
                time x= t where TOD t _= unsafePerformIO $ getClockTime
           nubBy1 (s,_)(s',_)= s==s'
           outobjs :: [Data1 op a]
           outobjs= apply  t objs
   
  
instance  (Show a, Read a, Show op, Read op
          ,Protocol (URIHold,Id,Id,[Tr (Op op a)]) URIHold 
          ,SyncRepository (Tr (Op op a)) (Data1 op a) Id 
          ,T.IResource a
          ,T.IResource (Data1 op a)
          ,TransMap op a
          --,TransMap  (Op op) (Data1 op a)
          ,GetProto  a
          ,NTrans (Tr (Op op a)) (Data1 op a) ) 
          => Cluster (Tr (Op op a)) (Data1 op a) URIHold Id where
          
  tvMyNode= tv where [tv]= unsafePerformIO $ getTVarsIO [(MyNode nod0 :: (Data1 op a))]
            
  reconnectAction id = do
           mall <- getResource $ AllObjects undefined undefined ::  IO (Maybe (Data1 op a))
           case mall of
            Nothing -> return []
            Just (AllObjects n all) ->   do
               let (all1,_)= unzip . filter (\(_,mod)->  mod>t) $ nubBy nubBy1 all
               --mynode <- readMVar myNodeName
               justGetResources $ map getProto ( all1 \\ ["PendingTrans"++"MyNode"]) ::IO [Data1 op a]

           where 
           Id (TTOD t _) _ _= id
           nubBy1 (s,_)(s',_)= s==s'





  initCluster myurl mclusterurl interval= do 
        --T.clearSyncCacheProc (T.refcache :: T.Cache (Data1 op a)) 10 T.defaultCheck 10  `debug` "initCluster"
        let myuri= makeURI myurl
        let port= uriPort1 myuri
        withResources [] (\_->[PendingTrans [] :: Data1 op a])
        modifyMVar_   myNodeName (\_->  return myurl)
                          
          
        forkIO $  setCallback port (receiveTrans ::(URIHold,Id,Id,[Tr (Op op a)])  -> IO (URIHold,Id,Id,[Tr (Op op a)])) 
        threadDelay 1000000
        forkIO $ loop interval (sendTranss :: IO URIHold)                  
        threadDelay 1000000
        forkIO $ loop interval (polling :: IO (Tr (Op op a)))
      

        case mclusterurl of
          Just clusterurl -> connect myuri clusterurl 
          Nothing -> return ()

        atomically $ do
                           MyNode nod <- readTVar  tvMyNode :: STM (Data1 op a)
                           writeTVar tvMyNode $ MyNode nod{uri= myuri}
          

        return myuri                                                            `debug` "return"

        where
        connect myuri clusterurl=do
          let clusteruri= makeURI clusterurl                                    `debug` ("clusterurl="++ show clusterurl)
          getTVarsIO[Node nod0{uri=clusteruri, active=ConnectSent} :: (Data1 op a)]    --create the other computer node
          id <- genIdNode
          mts <- send (myuri, id0, id0,[Tr id [] Connect:: Tr (Op op a)])  clusteruri --send a request to a node of the cluster
          case mts of
              Just msg  -> do
                         receive msg
                         return()
                             
            
              Nothing -> do
                 error $ "cluster at adddress "++clusterurl++" not reached"
                 


          threadDelay 1000000
  
          atomically $ do   -- wait until the node has been created
              MyNode nod <- readTVar tvMyNode :: STM (Data1 op a)
              if nod==nod0 
                then retry                                             `debug` "no node" 
                else return()
         
  
          return ()
          
  applyCSTrans  ts = lock >> doit `finally` unlock           `debug` "applyCSTrans"
            
    where
    lockReceive= unsafePerformIO $ newMVar True
    lock= takeMVar lockReceive   -- to queye all requests of all nodes
    unlock= putMVar lockReceive True


    doit= do
      ts1 <- atomically $ do
        MyNode mynode <-   readTVar tvMyNode                `debug` "doit"
        let nodeIds = nodesConected mynode
        Just tvtrans:tvnodes <-  unsafeIOToSTM $ getTVars $ PendingTrans u:[Node nod0{uri=URIHold n u}| n <- nodeIds]

        PendingTrans all <- readTVar tvtrans
        nodes <-  mapM readTVar $ map fromJust tvnodes

        let lastRec= if not $ null ts then getId $ last ts else lastReceived mynode

        let consId = case length nodes of
              0 -> lastRec
              1 -> let Node node=  head nodes in lastReceived node 
              _ -> let consIds=  map (\(Node node) -> lastReceived node) nodes 
                                 ++ map (\(Node node) -> consolidatedId node) nodes
    
                   in  minimum  consIds
       
        let eqID x y= getId x==getId y
        let tss =  nubBy eqID $ sortBy compareIds (all ++ ts)                      `debug` ("consId= "++show consId)
        let (ts1,ts2) =  if null $ nodesConected mynode
                         then (tss,[])
                         else span (\t-> getId t<= consId) tss
 
        writeTVar tvtrans $ PendingTrans ts2                          `debug` ("PendingTrans: "++ show ts2)
        writeTVar tvMyNode $ MyNode mynode{consolidatedId=consId}
        return ts1
        
      applyTrans ts1                                                 `debug` "applyTrans"
      MyNode mynode <- atomically $ readTVar tvMyNode   
      print ""   `debug` ("lastRec in applyCSTrans"++ show ( lastReceived mynode))
      return ()

     where
     u=undefined
     
  polling= do
      t<- emptyTranss  
      let isAlone= atomically $ readTVar tvMyNode >>= \(MyNode Nod{nodesConected=n}) -> return n                                             
      alone <- isAlone 
      case alone of
        [] -> return t
        _  -> do
          handle(\e ->do{print e;return t}) $do
              addTrans t 
              return t
  

  transToSend   lastRec  = do
    PendingTrans pendingTranss <- justGetResource $ PendingTrans undefined :: IO (Data1 op a)

    let f t=getId t > lastRec 
    return .  sortBy compareIds $ filter  f  pendingTranss         `debug` ("transtosend PendingTrans= "++show pendingTranss)

  
  receive    (senderNode,lastRec,consolidated,ts) = do
  
    [mtvnode] <- getTVars [Node nod0{uri=senderNode}]   `debug` "Receive" ::IO [Maybe (TVar (Data1 op a))] 
   
    (tvnode, mynode)<-  atomically (do
    
        MyNode mynode <-  readTVar tvMyNode
        case mtvnode of
        
          Nothing -> do 
              let node= Node nod0{uri=senderNode,lastReceived=id0               `debug` "clusteruri Nothing"
                                     ,consolidatedId=id0,active=Inactive}

              [tv] <- unsafeIOToSTM $ getTVarsIO [node]   -- create the node in the cache
              return (tv,mynode)
                    
          Just tv -> return (tv,mynode)`debug` "clusteruri creado")                                              
          

    let URIHold myurl _= uri mynode 
    let myuri= uri mynode
                        


    Node nnode <- atomically $ readTVar tvnode            
   
    let prevLastSent= lastReceived nnode                       
    let node= nnode{ lastReceived= lastRec, consolidatedId= consolidated}
    atomically $ writeTVar tvnode $ Node node
    
    let consMyNode= lastReceived mynode
    let ts'= dropWhile (\t-> getId t <= consMyNode) ts  --to avoid to apply already processed 
    
    let lastRecMyNode= if not $ null ts then getId $ last ts else lastReceived mynode
    let mynode'=  mynode{lastReceived= lastRecMyNode}
    atomically $ writeTVar tvMyNode $ MyNode mynode' `debug` ("lastRec node="++ show lastRecMyNode)

    node' <- case (active node, ts') of

      (Active, ts) -> do
               applyCSTrans ts
               return node
    
      (Inactive,[Tr id nodes Connect]) -> do
               return node{active= ConnectReceived (length nodes) prevLastSent} `debug` ("new state= ConnectReceived")
             
      (Inactive, ts) -> do
               applyCSTrans . filter commutative $ ts'
               return node{active= ToSendConnect}   `debug` ("new state= ToSendConnect")

      (ConnectSent,ts@[Tr _ _ (AddObjects os)]) -> do
               applyCSTrans ts
               let URIHold url _= senderNode
               let mynode''= mynode'{nodesConected= url:nodesConected mynode'}
               atomically $ writeTVar  tvMyNode $ MyNode mynode''
               return node{active= Active}             `debug` ("new state= Active")

      (ConnectSent,[]) -> do
               return $ node{active= ToSendAddObjects prevLastSent}  `debug` ("new state= ToSendAddObjects")

      x -> error $ "state not expected" ++ show x

    atomically $ writeTVar tvnode $ Node node'      `debug` ("receive new state= "++ show (active node'))   
    mnode<- atomically $   readTVar tvMyNode
    return (mnode, Node node', tvnode)              `debug` (let MyNode node= mnode in "lasRec antes de respond"++ show (lastReceived node))
             
    --receiveTrans :: (nodeId,Id,Id,[t])  -> IO (nodeId,Id,Id,[t])       
  respond (MyNode mynode, Node node, tvnode)= do
      let myuri= uri mynode
      let lastRec= lastReceived mynode                 


      case active node of

         Active -> do   
               tsToSend<- transToSend $ consolidatedId node
               return (myuri,lastRec `debug` ("respond lastRec=" ++ show (lastReceived node)), consolidatedId mynode,tsToSend)


         Inactive -> error $ "respond for a inactive node: "++show node         
          
         ConnectReceived  nodes prevLastSent -> do
            -- one side must drop its non-commutative transactions
              if length (nodesConected mynode) >= nodes 
               then do
                  --let prevLastSent= lastReceived node
                  tsOfReconnection <- reconnectAction  prevLastSent -- :: IO [Data1  op a]
                  id <- genIdNode
                  let t= Tr id [] $ AddObjects  tsOfReconnection    
                  atomically $ do 
                     writeTVar tvnode $ Node node{active=Active,lastReceived=prevLastSent,consolidatedId=prevLastSent}   `debug` ("new state= Active")
                     let URIHold url _= uri node
                     let mynode'= mynode{nodesConected= url:nodesConected mynode}
                     writeTVar  tvMyNode $ MyNode mynode'

                  return (myuri,lastRec,consolidatedId mynode,[t])
               else 
                  return (myuri,lastRec,consolidatedId mynode,[])

         ToSendAddObjects prevLastSent-> do
                  tsOfReconnection <- reconnectAction  prevLastSent -- :: IO [Data1  op a]
                  
                  id <- genIdNode
                  let t= Tr id [] $ AddObjects  tsOfReconnection    
                  atomically $ do
                     writeTVar tvnode $ Node node{active=Active}    `debug` ("new state= Active")
                     let URIHold url _= uri node
                     let mynode'= mynode{nodesConected= url:nodesConected mynode}
                     writeTVar  tvMyNode $ MyNode mynode'

                  return (myuri,lastRec,consolidatedId mynode,[t])

         ToSendConnect -> do  
                  id <- genIdNode
                  let conn = Tr id (nodesConected mynode) Connect 
                  atomically $ writeTVar tvnode $ Node node{active=ConnectSent}    `debug` ("new state= ConnectSent") 
  
                  return (myuri,lastRec,consolidatedId mynode,[conn])
              

  sendTranss=  do
   MyNode mynode <- atomically $ readTVar tvMyNode              `debug` "sendTrans"
   mtvnodes <- getTVars [getProto n | n <- nodesConected mynode]  :: IO [Maybe(TVar(Data1 op a))]
   let tvnodes = map fromJust mtvnodes

   handle(\e ->do {print e; return (uri mynode)}) $ do
     flags <- mapM  (send1 $ MyNode mynode)  tvnodes 
     if foldr  (||) False flags then return ()  -- if all are inactive
         else applyCSTrans  []  --to process local transactions even if no received transactions or no cluster
     return (uri  mynode) `debug` "end sendTrans"

     where
     send1 :: Data1 op a -> TVar (Data1 op a) -> IO Bool
     send1 (MyNode mynode) tvnode = do
        Node node <- atomically $ readTVar tvnode :: IO (Data1 op a)
        if  active node /= Active  then return False else do

          resp<-  respond (MyNode mynode,  Node node, tvnode) :: IO (URIHold,Id,Id,[Tr (Op op a) ] )            
          case resp of
            (_,_,_,[]) -> return True                      `debug`   "nada que enviar"
            _  -> do 
                     sendT resp   tvnode   (Node node)
                     return True 
        where
         sendT :: (URIHold,Id,Id,[Tr (Op op a) ] ) -> TVar (Data1 op a) -> Data1 op a -> IO ()
         sendT resp  tvnode (Node node) = do
           mts <- send resp (uri node)
           case mts of
              Just msg  -> do
                         receive msg
                         return()
                             
            
              Nothing -> do
                 atomically $ do
                    writeTVar tvnode $ Node node{ active= Inactive}
                    let URIHold url _ = uri node
                    writeTVar tvMyNode $ MyNode mynode{nodesConected= nodesConected mynode \\ [url]}
                 return ()


addTransaction :: Cluster  (Tr (Op op a)) (Data1 op a) URIHold Id =>[String] -> op  -> IO ()
addTransaction keys op  =  createTrans keys op >>= addTrans 

createTrans :: Cluster  (Tr (Op op a)) (Data1 op a) URIHold Id => [String] ->  op  -> IO (Tr (Op op a))
createTrans keys op = do
    id <- genIdNode                              
    return $ Tr id keys  (Op op)

      

compareIds t t'= compare (getId t) (getId t')

justGetResource r = getResource r >>= \r' -> return $ assert (isJust r') (fromJust r') 


justGetResources rs= getResources rs >>=  \rs' -> mapM (\r ->return $ assert (isJust r) fromJust r) rs'



      
loop interval f=loop1 
        where 
        loop1 =  do 
                 f
                 threadDelay (fromIntegral $ interval * 1000000)                    `debug` "loop"
                 loop1  
