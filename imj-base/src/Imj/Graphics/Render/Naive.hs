
module Imj.Graphics.Render.Naive
          ( NaiveDraw(..)
          ) where

import           Data.Text(unpack)

import           Control.Monad.Reader(liftIO)

import           System.IO(hFlush, stdout)
import           System.Console.ANSI(setCursorPosition, clearFromCursorToScreenEnd)

import           Imj.Geo.Discrete
import           Imj.Graphics.Class.Canvas
import           Imj.Graphics.Class.Draw
import           Imj.Graphics.Class.Render
import           Imj.Graphics.Color.Types
import           Imj.Graphics.Font
import           Imj.Graphics.UI.RectArea
import           Imj.Timing

{- | FOR TESTS ONLY. For production, please use "Imj.Graphics.Render.Delta".

Does not support the notion of 'Scissor', hence drawing locations will
not be filtered.

Naive rendering for the terminal : at every call it sends @color@ and
@position@ change commands, hence
<https://en.wikipedia.org/wiki/Screen_tearing screen tearing> happens very quickly as
a consequence of stdout buffer being automatically flushed to avoid overflow.
-}
data NaiveDraw = NaiveDraw

move' :: Coords Pos -> IO ()
move' (Coords (Coord y) (Coord x)) =
  setCursorPosition y x -- with redundancy, as we don't keep track of the current position.

color :: LayeredColor -> IO ()
color = putStr . colorChange Nothing -- with redundancy, as we don't keep track of the current color.

-- | Direct draw to stdout : don't use for production, this is for tests only
-- and creates heavy screen tearing.
--
-- For production, please use "Imj.Graphics.Render.Delta"
--
-- Does not support the notion of 'Scissor', hence drawing locations will
-- not be filtered.
instance Draw NaiveDraw where
    -- | This is incorrect but the goal of 'NaiveDraw' is not to provide every functionality of 'Draw'.
    --
    -- For production, please use "Imj.Graphics.Render.Delta"
    setScissor _ _ = return ()

    getScissor' _ = return maxRectArea

    -- | This is incorrect but the goal of 'NaiveDraw' is not to provide every functionality of 'Draw'.
    --
    -- For production, please use "Imj.Graphics.Render.Delta"
    fill'           _ _ c    = liftIO $ color c
                                      >> setCursorPosition 0 0
                                      >> clearFromCursorToScreenEnd
    drawGlyph'      _ b c d   = liftIO $ move' c >> color d >> putChar (fst $ decodeGlyph b)
    drawGlyphs'     _ b c d e = liftIO $ move' d >> color e >> putStr (replicate b $ fst $ decodeGlyph c)
    drawTxt'       _ b c d   = liftIO $ move' c >> color d >> putStr (unpack b)
    drawStr'       _ b c d   = liftIO $ move' c >> color d >> putStr b
    {-# INLINABLE drawGlyph' #-}
    {-# INLINABLE drawGlyphs' #-}
    {-# INLINABLE drawTxt' #-}
    {-# INLINABLE drawStr' #-}
    {-# INLINABLE getScissor' #-}
    {-# INLINABLE setScissor #-}
    {-# INLINABLE fill' #-}

instance Canvas NaiveDraw where
    getTargetSize' _         = return Nothing
    onTargetChanged' _ = return $ Left "Not implemented"
    {-# INLINABLE getTargetSize' #-}

-- | Direct draw to stdout : don't use for production, this is for tests only
-- and creates heavy screen tearing.
instance Render NaiveDraw where
    renderToScreen' _         = liftIO $ do
      hFlush stdout
      return (Nothing, Right (zeroDuration, zeroDuration, zeroDuration))

    cycleRenderingOptions' _ _ _ =
      return $ Right ()
    applyPPUDelta _ _ =
      return $ Right ()
    applyFontMarginDelta _ _ =
      return $ Right ()

    {-# INLINABLE renderToScreen' #-}
    {-# INLINABLE cycleRenderingOptions' #-}
