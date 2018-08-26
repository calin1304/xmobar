-----------------------------------------------------------------------------
-- |
-- Module      :  Plugins.Monitors.Volume
-- Copyright   :  (c) 2011, 2013, 2015 Thomas Tuegel
-- License     :  BSD-style (see LICENSE)
--
-- Maintainer  :  Jose A. Ortega Ruiz <jao@gnu.org>
-- Stability   :  unstable
-- Portability :  unportable
--
-- A monitor for ALSA soundcards
--
-----------------------------------------------------------------------------

module Plugins.Monitors.Volume
  ( runVolume
  , runVolumeWith
  , volumeConfig
  , options
  , defaultOpts
  , VolumeOpts
  ) where

import Control.Applicative ((<$>))
import Control.Monad ( liftM2, liftM3, mplus )
import Data.Traversable (sequenceA)
import Plugins.Monitors.Common
import Sound.ALSA.Mixer
import qualified Sound.ALSA.Exception as AE
import System.Console.GetOpt

volumeConfig :: IO MConfig
volumeConfig = mkMConfig "Vol: <volume>% <status>"
                         ["volume", "volumebar", "volumevbar", "dB","status", "volumeipat"]


data VolumeOpts = VolumeOpts
    { onString :: String
    , offString :: String
    , onColor :: Maybe String
    , offColor :: Maybe String
    , highDbThresh :: Float
    , lowDbThresh :: Float
    , volumeIconPattern :: Maybe IconPattern
    }

defaultOpts :: VolumeOpts
defaultOpts = VolumeOpts
    { onString = "[on] "
    , offString = "[off]"
    , onColor = Just "green"
    , offColor = Just "red"
    , highDbThresh = -5.0
    , lowDbThresh = -30.0
    , volumeIconPattern = Nothing
    }

options :: [OptDescr (VolumeOpts -> VolumeOpts)]
options =
    [ Option "O" ["on"] (ReqArg (\x o -> o { onString = x }) "") ""
    , Option "o" ["off"] (ReqArg (\x o -> o { offString = x }) "") ""
    , Option "" ["lowd"] (ReqArg (\x o -> o { lowDbThresh = read x }) "") ""
    , Option "" ["highd"] (ReqArg (\x o -> o { highDbThresh = read x }) "") ""
    , Option "C" ["onc"] (ReqArg (\x o -> o { onColor = Just x }) "") ""
    , Option "c" ["offc"] (ReqArg (\x o -> o { offColor = Just x }) "") ""
    , Option "" ["volume-icon-pattern"] (ReqArg (\x o ->
       o { volumeIconPattern = Just $ parseIconPattern x }) "") ""
    ]

parseOpts :: [String] -> IO VolumeOpts
parseOpts argv =
    case getOpt Permute options argv of
        (o, _, []) -> return $ foldr id defaultOpts o
        (_, _, errs) -> ioError . userError $ concat errs

percent :: Integer -> Integer -> Integer -> Float
percent v' lo' hi' = (v - lo) / (hi - lo)
  where v = fromIntegral v'
        lo = fromIntegral lo'
        hi = fromIntegral hi'

formatVol :: Integer -> Integer -> Integer -> Monitor String
formatVol lo hi v =
    showPercentWithColors $ percent v lo hi

formatVolBar :: Integer -> Integer -> Integer -> Monitor String
formatVolBar lo hi v =
    showPercentBar (100 * x) x where x = percent v lo hi

formatVolVBar :: Integer -> Integer -> Integer -> Monitor String
formatVolVBar lo hi v =
    showVerticalBar (100 * x) x where x = percent v lo hi

formatVolDStr :: Maybe IconPattern -> Integer -> Integer -> Integer -> Monitor String
formatVolDStr ipat lo hi v =
    showIconPattern ipat $ percent v lo hi

switchHelper :: VolumeOpts
             -> (VolumeOpts -> Maybe String)
             -> (VolumeOpts -> String)
             -> Monitor String
switchHelper opts cHelp strHelp = return $
    colorHelper (cHelp opts)
    ++ strHelp opts
    ++ maybe "" (const "</fc>") (cHelp opts)

formatSwitch :: VolumeOpts -> Bool -> Monitor String
formatSwitch opts True = switchHelper opts onColor onString
formatSwitch opts False = switchHelper opts offColor offString

colorHelper :: Maybe String -> String
colorHelper = maybe "" (\c -> "<fc=" ++ c ++ ">")

formatDb :: VolumeOpts -> Integer -> Monitor String
formatDb opts dbi = do
    h <- getConfigValue highColor
    m <- getConfigValue normalColor
    l <- getConfigValue lowColor
    d <- getConfigValue decDigits
    let db = fromIntegral dbi / 100.0
        digits = showDigits d db
        startColor | db >= highDbThresh opts = colorHelper h
                   | db < lowDbThresh opts = colorHelper l
                   | otherwise = colorHelper m
        stopColor | null startColor = ""
                  | otherwise = "</fc>"
    return $ startColor ++ digits ++ stopColor

runVolume :: String -> String -> [String] -> Monitor String
runVolume mixerName controlName argv = do
    opts <- io $ parseOpts argv
    runVolumeWith opts mixerName controlName

runVolumeWith :: VolumeOpts -> String -> String -> Monitor String
runVolumeWith opts mixerName controlName = do
    (lo, hi, val, db, sw) <- io readMixer
    p <- liftMonitor $ liftM3 formatVol lo hi val
    b <- liftMonitor $ liftM3 formatVolBar lo hi val
    v <- liftMonitor $ liftM3 formatVolVBar lo hi val
    d <- getFormatDB opts db
    s <- getFormatSwitch opts sw
    ipat <- liftMonitor $ liftM3 (formatVolDStr $ volumeIconPattern opts) lo hi val
    parseTemplate [p, b, v, d, s, ipat]

  where

    readMixer =
      AE.catch (withMixer mixerName $ \mixer -> do
                   control <- getControlByName mixer controlName
                   (lo, hi) <- liftMaybe $ getRange <$> volumeControl control
                   val <- getVal $ volumeControl control
                   db <- getDB $ volumeControl control
                   sw <- getSw $ switchControl control
                   return (lo, hi, val, db, sw))
                (const $ return (Nothing, Nothing, Nothing, Nothing, Nothing))

    volumeControl :: Maybe Control -> Maybe Volume
    volumeControl c = (playback . volume =<< c)
              `mplus` (capture . volume =<< c)
              `mplus` (common . volume =<< c)

    switchControl :: Maybe Control -> Maybe Switch
    switchControl c = (playback . switch =<< c)
              `mplus` (capture . switch =<< c)
              `mplus` (common . switch =<< c)

    liftMaybe :: Maybe (IO (a,b)) -> IO (Maybe a, Maybe b)
    liftMaybe = fmap (liftM2 (,) (fmap fst) (fmap snd)) . sequenceA

    liftMonitor :: Maybe (Monitor String) -> Monitor String
    liftMonitor Nothing = unavailable
    liftMonitor (Just m) = m

    channel v r = AE.catch (getChannel FrontLeft v) (const $ return $ Just r)

    getDB :: Maybe Volume -> IO (Maybe Integer)
    getDB Nothing = return Nothing
    getDB (Just v) = channel (dB v) 0

    getVal :: Maybe Volume -> IO (Maybe Integer)
    getVal Nothing = return Nothing
    getVal (Just v) = channel (value v) 0

    getSw :: Maybe Switch -> IO (Maybe Bool)
    getSw Nothing = return Nothing
    getSw (Just s) = channel s False

    getFormatDB :: VolumeOpts -> Maybe Integer -> Monitor String
    getFormatDB _ Nothing = unavailable
    getFormatDB opts (Just d) = formatDb opts d

    getFormatSwitch :: VolumeOpts -> Maybe Bool -> Monitor String
    getFormatSwitch _ Nothing = unavailable
    getFormatSwitch opts (Just sw) = formatSwitch opts sw

    unavailable = getConfigValue naString
