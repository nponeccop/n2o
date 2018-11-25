{-# LANGUAGE ScopedTypeVariables #-}
module Web.Nitro.Protocol where

import Control.Monad (forM_)
import Control.Monad.IO.Class
import qualified Data.Map.Strict as M
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8
import Data.IORef
import Network.N2O.Internal
import Web.Nitro.Internal

nitroProto :: (Show a) => Proto (N2OProto a) (StateRef a)
nitroProto message = do
  ref <- ask
  cx@Context {cxHandler = handle, cxDePickle = dePickle} <- getContext
  liftIO $ putStrLn ("NITRO : " ++ show message)
  case message of
    msg@(N2ONitro (NitroInit pid)) -> do
      handle Init
      actions <- getActions
      rendered <- renderActions' actions
      return $ Reply (reply rendered)
    msg@(N2ONitro (NitroPickle _source pickled linked)) -> do
      forM_ (M.toList linked) (uncurry put)
      depickled <- dePickle pickled
      case depickled of
        Just x -> do
          handle (Message x)
          actions <- getActions
          rendered <- renderActions' actions
          return $ Reply (reply rendered)
        _ -> return Unknown
    msg@(N2ONitro NitroDone) -> do
      handle Terminate
      return Empty
  where
    reply bs = Io bs BS.empty
    renderActions' actions =
      case actions of
        [] -> return BS.empty
        actions -> do
          putActions []
          first <- renderActions actions
          actions2 <- getActions
          second <- renderActions actions2
          putActions []
          return $ first <> C8.pack ";" <> second
