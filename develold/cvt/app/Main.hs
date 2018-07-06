{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TypeOperators              #-}


module Main where

import           Control.Applicative
import           Control.Concurrent         (forkIO, threadDelay)
import           Control.Concurrent.MVar
--import           Control.DeepSeq
import           Control.Monad
import           Control.Monad.IO.Class
import           Control.Monad.State
import           Control.Monad.Trans.Except
import           Data.Aeson
import           Data.ByteString.Lazy       as DBL hiding (elemIndex, length)
import           Data.Hashable
import           Data.IORef
import           Data.List
import           Data.Map                   as M
import           Data.Maybe
import qualified Data.Text                  as DT
import           Data.Typeable
import           Data.UUID
import           Data.UUID.Aeson
import           Data.UUID.V4
import           GHC.Generics
import           Network.Wai
import           Network.Wai.Handler.Warp   hiding (run)
import           Servant                    hiding (Handler)
import           Servant.API
import           System.IO
import           System.IO.Unsafe
import           Transient.Base
import           Transient.Internals
import           Transient.Move
import           Transient.Move.Utils


newtype VendorId = VendorId UUID
  deriving(Eq, Ord, Read, Show,FromHttpApiData)

newtype ItemId = ItemId UUID
  deriving(Eq, Ord,Read,Show, FromHttpApiData)

type ItemApi =
  "item" :> Get '[JSON] [Item] :<|>
  "item" :> Capture "itemId" ItemId :> Capture "vendorId" VendorId :> Get '[JSON] Item

itemApi :: Proxy ItemApi
itemApi = Proxy

-- * app

instance FromHttpApiData UUID where
  parseUrlPiece t = case fromText t of
    Just u -> Right u
    Nothing -> Left "Invalid UUID"

run :: IO ()
run = do
  let port = 3000
      settings =
        setPort port $
        setBeforeMainLoop (hPutStrLn stderr ("listening on port " ++ show port)) defaultSettings
  runSettings settings =<< mkApp

mkApp :: IO Application
mkApp = return $ serve itemApi server

server :: Server ItemApi
server =
  getItems :<|>
  getItemById

type Handler = ExceptT ServantErr IO

getItems :: Handler [Item]
getItems = return [exampleItem]

getItemById :: ItemId -> VendorId -> Handler Item
getItemById i v = do
    liftIO $ putMVar rquery (i, v)
    liftIO $ takeMVar rresponse




exampleItem :: Item
exampleItem = Item 0 "example item"


data Item
  = Item {
    itemId   :: Int,
    itemText :: String
  }
  deriving (Eq, Show, Generic, Read)

instance ToJSON Item
instance FromJSON Item


hashmap :: Cloud (Map (VendorId, ItemId) Int)
hashmap = onAll (return $ M.fromList [--((VendorId . fromJust $ fromText "bacd5f20-8b46-4790-b93f-73c47b8def72", ItemId . fromJust $ fromText "db6af727-1007-4cae-bd24-f653b1c6e94e"), 10)])
                                      ((VendorId . fromJust $ fromText "8f833732-a199-4a74-aa55-a6cd7b19ab66", ItemId . fromJust $ fromText "d6693304-3849-4e69-ae31-1421ea320de4"), 20)])


{-# NOINLINE ref #-}
ref = unsafePerformIO $ newIORef (error "state should have been written here!")

--main :: IO ()
--main = runCloudIO' $ do
--    seed <- lliftIO $ createNode "localhost" 8000
--    node <- lliftIO $ createNode "localhost" 8000
--    m <- hashmap
--    connect node seed
--    local $ gets mfData >>= liftIO . writeIORef ref
--    nodes <- onAll getNodes
--    lliftIO $ print $ length nodes
--    -- let num = fromJust $ elemIndex node (sort nodes)
--    -- quant <- runAt (nodes !! num) $ return $ M.lookup num m
--    -- lliftIO $ print quant
--    local $ async run

rquery= unsafePerformIO $ newEmptyMVar

rresponse= unsafePerformIO $ newEmptyMVar

main :: IO ()
main = keep' $   async run <|>  initNode (inputNodes <|> cluster)

cluster= do

--    lliftIO $ print $ length nodes

    (i@(ItemId iid), v@(VendorId vid)) <- local . waitEvents $ takeMVar rquery

    let h = abs $ hash $ toString iid ++ toString vid

    onAll $ liftIO $  print $ "hash" ++ show h

    node <- local $ do
       nodes <-  getNodes
       return () !> ("numnodes", length nodes)

       let num = h `rem` length nodes
       let node= sort nodes !! num
       return node !> ("calling node",node)

    m <- hashmap
    quant <- runAt node  $ return $ M.lookup (v, i) m

    localIO $ putMVar rresponse $ case quant of
      Just q  -> (Item q "Item 1")
      Nothing -> (Item 0 "Item Unknown")
