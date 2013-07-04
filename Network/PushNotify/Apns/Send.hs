-- GSoC 2013 - Communicating with mobile devices.

{-# LANGUAGE OverloadedStrings, TypeFamilies, TemplateHaskell,
             QuasiQuotes, MultiParamTypeClasses, GeneralizedNewtypeDeriving, FlexibleContexts, GADTs #-}

-- | This Module define the main function to send Push Notifications through Apple Push Notification Service.
module Network.PushNotify.Apns.Send (sendAPNS) where

import Network.PushNotify.Apns.Types
import Network.PushNotify.Apns.Constants

import Data.Convertible             (convert)
import Data.Default
import Data.Serialize
import Data.Text.Encoding           (encodeUtf8)
import Data.Text                    (unpack)
import Data.Time.Clock.POSIX
import Data.Time.Clock
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as LB
import qualified Data.Aeson.Encode as AE
import Network.Connection
import Network.Socket.Internal      (PortNumber(PortNum))
import Network.TLS.Extra            (fileReadCertificate,fileReadPrivateKey)

connParams :: Env -> ConnectionParams
connParams env = ConnectionParams{
                connectionHostname = case env of
                                        Development -> cDEVELOPMENT_URL
                                        Production  -> cPRODUCTION_URL
            ,   connectionPort     = case env of
                                        Development -> fromInteger cDEVELOPMENT_PORT
                                        Production  -> fromInteger cPRODUCTION_PORT
            ,   connectionUseSecure = TLSSettings defaultParamsClient{
                                            w
                                        ,   s
                                        } --Just def
            ,   connectionUseSocks = Nothing
            }

-- | 'sendAPNS' sends the message through a APNS Server.
sendAPNS :: APNSAppConfig -> APNSmessage -> IO ()
sendAPNS config msg = do
        let env = environment config
        ctime      <- getPOSIXTime
        cContext   <- initConnectionContext
        connection <- connectTo cContext $ connParams env
        connectionPut connection $ runPut $ createPut msg ctime

createPut :: APNSmessage -> NominalDiffTime -> Put
createPut msg ctime = do
   let
       btoken     = encodeUtf8 $ deviceToken msg -- I have to check if encodeUtf8 is the appropiate function.
       bpayload   = AE.encode msg
       expiryTime = case expiry msg of
                      Nothing ->  round (ctime + posixDayLength) -- One day for default
                      Just t  ->  round (utcTimeToPOSIXSeconds t)
   if (LB.length bpayload > 256)
      then fail "Too long payload"
      else do
            putWord8 1
            putWord32be 10 -- identifier
            putWord32be expiryTime
            putWord16be $ convert $ B.length btoken
            putByteString btoken
            putWord16be $ convert $ LB.length bpayload
            putLazyByteString bpayload


