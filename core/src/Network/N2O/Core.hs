{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
module Network.N2O.Core where

import Data.BERT
import Data.IORef
import qualified Data.Map.Strict as M
import qualified Data.Binary as B
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text.Lazy as TL
import Control.Exception (SomeException)
import Network.N2O.Types

-- | @Term -> Msg@ encoder
encodeBert :: Term -> Msg
encodeBert = MsgBin . B.encode
-- | @Term -> Msg@ decoder
decodeBert :: Msg -> Maybe Term
decodeBert (MsgBin bin) =
  case B.decodeOrFail bin of
    Right (_,_,term) -> Just term
    _ -> Nothing
decodeBert (MsgInit pid) = Just $ TupleTerm [AtomTerm "init", BytelistTerm pid]
decodeBert MsgTerminate = Just $ AtomTerm "terminate"
decodeBert _ = Nothing

mkCx = Cx
  { cxReq = undefined
  , cxHandler = undefined
  , cxMiddleware = []
  , cxDePickle = undefined
  , cxPickle = undefined
  , cxProtos = []
  , cxEncoder = undefined
  , cxDecoder = undefined
  , cxState = M.empty
  }

mkReq = Req { reqPath = "/", reqMeth = "GET", reqVers = "HTTP/1.1", reqHead = [] }

nop :: Return
nop = Reply (MsgBin BSL.empty)

-- | N2O protocol loop
protoRun :: Msg -> N2O f a b Return
protoRun msg = do
  ref <- ask
  cx@Cx {cxProtos = protos, cxDecoder = decode} <- lift $ readIORef ref
  loop [] msg protos decode
  where
    loop _ _ [] _ = return nop
    loop acc msg (proto:protos) decoder = do
      let mbDecoded = decoder msg
      case mbDecoded of
        Just decoded -> do
          res <- protoInfo proto decoded
          case res of
            Unknown -> loop acc msg protos decoder
            Reply msg1 -> return $ Reply msg1
            a -> loop (a : acc) msg protos decoder
        _ -> loop acc msg protos decoder