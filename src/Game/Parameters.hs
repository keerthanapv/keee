{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Game.Parameters(
        GameParameters(..)
      , getGameParameters
      , WorldShape(..)
      , WallType(..)
      , RandomParameters(..)
      , Strategy(..)
      ) where

import           Imajuscule.Prelude

import           Color

import           Game.World
import           Game.World.Evolution
import           Game.World.Space
import           Game.World.Size
import           Game.World.Embedded

import           Geo.Discrete

import           IO.Blocking

import           Render.Console

import           Timing

data GameParameters = GameParameters {
    _gameParamsWorldShape :: !WorldShape
  , _gameParamsWallTypes :: !WallType
}

minRandomBlockSize :: Int
minRandomBlockSize = 6 -- using 4 it once took a very long time (one minute, then I killed the process)
                       -- 6 has always been ok

initialParameters :: GameParameters
initialParameters = GameParameters Square None

getGameParameters :: IORef Buffers -> IO GameParameters
getGameParameters = update initialParameters

update :: GameParameters -> IORef Buffers -> IO GameParameters
update params ctxt =
  render params ctxt >>
    getCharThenFlush >>= either
      (\_ -> return params)
      (\c -> if c == ' '
              then
                return params
              else
                update (updateFromChar c params) ctxt)


updateFromChar :: Char -> GameParameters -> GameParameters
updateFromChar c p@(GameParameters shape wallType) =
  case c of
    '1' -> GameParameters Square wallType
    '2' -> GameParameters Rectangle2x1 wallType
    'e' -> GameParameters shape None
    'r' -> GameParameters shape Deterministic
    't' -> GameParameters shape (Random $ RandomParameters minRandomBlockSize StrictlyOneComponent)
    _ -> p

render :: GameParameters -> IORef Buffers -> IO ()
render (GameParameters shape wall) ctxt' = do
  let worldSize@(WorldSize (Coords (Row rs) (Col cs))) = worldSizeFromLevel 1 shape
  ew <- mkEmbeddedWorld ctxt' worldSize
  case ew of
    Left err -> error err
    Right rew@(EmbeddedWorld _ ul ctxt) -> do
      beginFrame
      world@(World _ _ _ space _ _) <- mkWorld rew worldSize wall [] 0
      _ <- renderSpace space ul ctxt >>=
        \worldCoords -> do
          renderWorld world
          let middle = move (quot cs 2) RIGHT worldCoords
              middleCenter = move (quot (rs-1) 2 ) Down middle
              middleLow    = move (rs-1)           Down middle
              leftMargin = 3
              left = move (quot (rs-1) 2 - leftMargin) LEFT middleCenter
          renderAlignedTxt Centered "Game configuration" configColors (translateInDir Down middle) ctxt
            >>= \ pos ->
              renderAlignedTxt_ Centered "------------------" configColors pos ctxt

          translateInDir Down <$> drawTxt "- World shape" configColors (move 5 Up left) ctxt
            >>= \ pos ->
              drawTxt "'1' -> width = height" configColors pos ctxt
                >>= \pos2 ->
                  renderTxt_ "'2' -> width = 2 x height" configColors pos2 ctxt
          translateInDir Down <$> drawTxt "- World walls" configColors left ctxt
            >>= \pos ->
              drawTxt "'e' -> no walls" configColors pos ctxt >>=
                \pos2 ->
                  drawTxt "'r' -> deterministic walls" configColors pos2 ctxt
                    >>= \pos3 ->
                      renderTxt_ "'t' -> random walls" configColors pos3 ctxt

          renderAlignedTxt_ Centered "Hit 'Space' to start game" configColors (translateInDir Up middleLow) ctxt
          t <- getCurrentTime
          let infos = (mkFrameSpec worldFrameColors world ctxt, (([""],[""]),([""],[""])))
              worldAnimation = mkWorldAnimation infos infos t
          renderWorldAnimation worldAnimation ctxt
      endFrame ctxt
