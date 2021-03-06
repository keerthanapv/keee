{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE BangPatterns #-}

module Imj.Server.Color
      ( ColorScheme(..)
      , mkCenterColor
      , mkClientColorFromCenter
      ) where

import           Imj.Prelude

import           Data.Char(toLower)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import           Data.Map.Strict(Map)
import           Options.Applicative(short, long, option, help, str, ReadM, readerError)
import           Text.Read(readMaybe)

import           Imj.Arg.Class
import           Imj.ClientView.Types
import           Imj.Graphics.Color.Types
import           Imj.Graphics.Color
import           Imj.Timing

data ColorScheme =
    UseServerStartTime
  | ColorScheme {-# UNPACK #-} !(Color8 Foreground)
  deriving(Generic, Show)
instance NFData ColorScheme
instance Arg ColorScheme where
  parseArg =
    Just $
      option srvColorSchemeArg
       (  long "colorScheme"
       <> short 'c'
       <> help (
       "Defines a rgb color from which player colors are deduced, cycling through same-intensity colors. " ++
       "Possible values are: " ++
       descPredefinedColors ++
       ", " ++
       "'rgb' | '\"r g b\"' where r,g,b are one of {0,1,2,3,4,5}, " ++
       "'time' to chose colors based on server start time. " ++
       "Default is 322 / \"3 2 2\". Incompatible with --serverName."
       ))

    where

     srvColorSchemeArg :: ReadM ColorScheme
     srvColorSchemeArg = map toLower <$> str >>= \lowercase -> do
       let err = readerError $
            "Encountered an invalid color scheme:\n\t" ++
            lowercase ++
            "\nAccepted values are:" ++
            "\n - one of " ++ descPredefinedColors ++
            "\n - 'rgb' | '\"r g b\"' where r,g,b are one of 0,1,2,3,4,5 (pure red is for example 500 / \"5 0 0\")" ++
            "\n - 'time'"
           asRGB l = case catMaybes $ map (readMaybe . (:[])) l of
             [r,g,b] -> either (const err) (return . ColorScheme) $ userRgb r g b
             _ -> err
       maybe
         (case lowercase of
           "time" -> return UseServerStartTime
           l@[_ ,_ ,_]     -> asRGB l
           [r,' ',g,' ',b] -> asRGB [r,g,b]
           _ -> err)
         (return . ColorScheme)
         $ predefinedColor lowercase

mkCenterColor :: ColorScheme -> IO (Color8 Foreground)
mkCenterColor (ColorScheme c) = return c
mkCenterColor UseServerStartTime = do
  t <- getCurrentSecond
  let !ref = rgb 3 2 0
      nColors = countHuesOfSameIntensity ref
      n = t `mod` nColors
  return $ rotateHue (fromIntegral n / fromIntegral nColors) ref

-- | This function assumes that 'ClientId's start at 0 and are ascending.
--
-- It will cycle through the colors of same intensity than the color passed as argument.
mkClientColorFromCenter :: ClientId
                        -> Color8 Foreground
                        -> Color8 Foreground
mkClientColorFromCenter i ref =
  let nColors = countHuesOfSameIntensity ref
      -- we want the following mapping:
      -- 0 -> 0
      -- 1 -> 1
      -- 2 -> -1
      -- 3 -> 2
      -- 4 -> -2
      -- ...
      dist = quot (succ i) 2
      n' = fromIntegral dist `mod` nColors
      n = if odd i then n' else -n'
  in rotateHue (fromIntegral n / fromIntegral nColors) ref


predefinedColor :: String -> Maybe (Color8 Foreground)
predefinedColor = flip Map.lookup predefinedColors

descPredefinedColors :: String
descPredefinedColors =
  "{'" ++
  List.intercalate "','" (Map.keys predefinedColors) ++
  "'}"

predefinedColors :: Map String (Color8 Foreground)
predefinedColors = Map.fromList
  [ ("blue",     rgb 0 3 5)
  , ("violet",   rgb 1 0 3)
  , ("orange" ,  rgb 4 2 1)
  , ("olive"  ,  rgb 3 3 0)
  , ("reddish" , rgb 3 2 2)
  ]
