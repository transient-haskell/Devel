{-# OPTIONS  -fglasgow-exts  #-}
module Cluster where

import Control.Concurrent
import System.IO.Unsafe
import Data.List
import System.Time
import Transaction
import Debug.Trace
import Control.Monad
import Control.Concurrent.STM(TVar)

debug a b= trace b a



class Trans t  a id  => SyncRepository t a id | t-> a, t->id  where
   applyTrans :: [t] -> IO ()
   addTrans :: t -> IO ()
   emptyTranss :: IO t                   -- the null transaction 

data CClockTime= TTOD Integer Integer deriving (Read, Show, Eq, Ord)
         
-- transactions where the id of the transactions include the  node number in the cluster
type NodeName=  String 

data Seq = Seq Int deriving (Eq,Ord, Read, Show)

data Id= Id {time::CClockTime, seq :: Seq, node:: NodeName}  deriving (Eq,Read,Show)

id0= Id (TTOD 0 0) (Seq 0) ""

genId= do liftM3 Id getTime genSeq  (return  "")
          
getTime=   do
            TOD t1 t2 <-getClockTime
            return $ TTOD t1 t2
            
seqVar:: MVar Int
seqVar= unsafePerformIO $ newMVar 0

genSeq= liftM Seq  $ modifyMVar seqVar (\x -> let y=x+1 in return (y,y))
          

   

instance Ord Id where
  compare (Id t s n) (Id t' s' n')= 
           case compare t t' of
              LT -> LT
              GT -> GT
              EQ -> case compare n n' of
                    LT -> LT
                    GT -> GT
                    EQ ->  compare s s'


class Trans t a Id => NTrans t a  where
    getNode :: t -> String


class Protocol t nodeId | t ->nodeId, nodeId -> t where
   send :: t -> nodeId -> IO (Maybe t)
   setCallback :: Int -> (t -> IO t) ->IO()
   
 --remoteExec
 --exec
 --redirect
 



myNodeName = unsafePerformIO $ newMVar  ""

genIdNode :: IO Id
genIdNode = do
      id     <- genId
      mynode <- readMVar myNodeName
      return   id{node= mynode}



class (Protocol (nodeId,Id,Id,[t])  nodeId ,SyncRepository t a Id, NTrans t a ) => 
                      Cluster  t a nodeId id 
                        | nodeId->t, nodeId->a, nodeId->id
                         ,t->nodeId
                         ,a -> nodeId, t->a, a -> t 
                         ,id ->t, id->a, id->nodeId
                      
  where
  tvMyNode :: TVar a
  reconnectAction :: Id -> IO[a]
  initCluster :: String -> Maybe String -> Int -> IO nodeId
  applyCSTrans ::   [t] -> IO ()
  polling :: IO (t)
  transToSend ::   Id  -> IO [t]

  receive :: (nodeId,Id,Id,[t])  -> IO(a,a,TVar a)
  respond :: (a,a,TVar a) -> IO(nodeId,Id,Id,[t])
  
  receiveTrans :: (nodeId,Id,Id,[t])  -> IO (nodeId,Id,Id,[t])
  receiveTrans rq= receive rq >>= respond    `debug` "receiveTrans" 


  sendTranss :: IO nodeId
