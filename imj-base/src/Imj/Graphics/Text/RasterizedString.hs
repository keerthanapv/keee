{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE LambdaCase #-}

module Imj.Graphics.Text.RasterizedString
         ( RasterizedString
         , mkRasterizedString
         , drawVerticallyCentered
         -- TODO split
         , withFreeType
         , loadChar
         , getCharIndex
         ) where

import           Imj.Prelude

import           Control.Exception(bracket)
import           Control.Monad.IO.Class(MonadIO)

import           Foreign.Storable(peek, peekElemOff)
import           Foreign.Marshal(alloca)

import           Graphics.Rendering.FreeType.Internal(ft_Load_Char, ft_Get_Char_Index, ft_Done_FreeType, ft_Init_FreeType)
import           Graphics.Rendering.FreeType.Internal.Bitmap(width, rows, buffer)
import           Graphics.Rendering.FreeType.Internal.Face(glyph, FT_Face)
--import           Graphics.Rendering.FreeType.Internal.Vector(FT_Vector(FT_Vector))
import           Graphics.Rendering.FreeType.Internal.Library(FT_Library)
import           Graphics.Rendering.FreeType.Internal.GlyphSlot(bitmap)
import           Graphics.Rendering.FreeType.Internal.PrimitiveTypes(FT_UInt, ft_LOAD_RENDER)

import           Data.Char(ord)

import           Imj.Geo.Discrete.Types

--import           Imj.Graphics.Class.DiscreteInterpolation
import           Imj.Graphics.Class.HasSizedFace
import qualified Imj.Graphics.Class.Positionable as Pos
import           Imj.Graphics.Color
import           Imj.Graphics.Font
import           Imj.Graphics.Render
import           Imj.Util

data RasterizedString = RasterizedString {
    _str :: !String
  , _face :: !SizedFace
  , _srBBox :: !Size
}
instance Pos.Positionable RasterizedString where
  height (RasterizedString _ _ (Size h _)) = h
  width (RasterizedString _ _ (Size _ w)) = w
  drawAt (RasterizedString str (SizedFace face _) (Size h _)) (Coords refY refX) =
    rasterizeString face str 1 $ \char c@(Coords y x) value ->
      when (value > 0) $
        drawGlyph (textGlyph char) (sumCoords ref $ Coords (-y) x) $ onBlack $ fg $ dist c
   where
    ref = Coords (refY + fromIntegral h) refX
    fg d =
      let v = quot (d+2) 6
      --in interpolate (rgb 2 1 0) (rgb 5 4 0) v
      in gray $ clamp (4 + 2*v) 0 23

{-# INLINE dist #-}
dist :: Coords Pos -> Int
dist (Coords (Coord y) (Coord x)) = x+y

mkRasterizedString :: String -> SizedFace -> IO RasterizedString
mkRasterizedString str sizedFace@(SizedFace face _) =
  RasterizedString str sizedFace <$> getRasterizedStringSize face str 1

drawVerticallyCentered :: (Pos.Positionable a
                         , MonadIO m
                         , MonadReader e m, Draw e)
                       => Coords Pos
                       -- ^ ref Coords
                       -> a
                       -> m ()
drawVerticallyCentered (Coords yRef xRef) p = do
  _ <- Pos.drawAligned p $ Pos.mkCentered $ Coords (yRef - quot (fromIntegral h) 2) xRef
  return ()
 where
  h = Pos.height p

charForSizeOfSpace :: Char
charForSizeOfSpace = '-'

getRasterizedStringSize :: FT_Face
                        -> String
                        -- ^ The title text
                        -> Length Width
                        -- ^ The number of whitespace between letters
                        -> IO Size
getRasterizedStringSize face str interLetterSpaces =
  foldM
    (\(wi,he) c -> do
      if c == ' '
        then
          loadChar face charForSizeOfSpace
        else
          loadChar face c
      slot <- peek $ glyph face
      bm <- peek $ bitmap slot
      return (wi + fromIntegral (width bm) + interLetterSpaces
            , max he $ fromIntegral $ rows bm))
    (-interLetterSpaces, 0)
    str
    >>= \(accW, accH) -> return $ Size accH (max 0 accW)

rasterizeString :: (MonadIO m)
                => FT_Face
                -> String
                -- ^ The title text
                -> Length Width
                -- ^ The number of whitespace between letters
                -> (Char -> Coords Pos -> Int -> m ())
                -> m ()
rasterizeString face str interLetterSpaces f =
  foldM_
    (\pos c -> do
      liftIO $ if c == ' '
              then
                loadChar face charForSizeOfSpace
              else
                loadChar face c
      slot <- liftIO $ peek $ glyph face
      bm <- liftIO $ peek $ bitmap slot
      let w = fromIntegral $ width bm
          h = fromIntegral $ rows bm
          buf = buffer bm
      when (c /= ' ') $
       forM_
        [0..pred h :: Int]
        (\j ->
          forM_
            [0..pred w :: Int]
            (\i -> do
              let idx = i + j * w
              signed <- fromIntegral <$> liftIO (peekElemOff buf idx)
              let unsigned =
                    if signed < 0
                      then
                        256 + signed
                      else
                        signed :: Int
              f c (sumCoords pos $ Coords (fromIntegral (pred h) - fromIntegral j) (fromIntegral i)) unsigned))
      return $ Pos.move (w + fromIntegral interLetterSpaces) RIGHT pos)
    zeroCoords str

------------------------ -- TODO split

loadChar :: FT_Face -> Char -> IO ()
loadChar face c =
  ft "Load_Char" $ ft_Load_Char face (fromIntegral $ ord c) ft_LOAD_RENDER

------------------------ -- TODO split

withFreeType :: (FT_Library -> IO a) -> IO a
withFreeType = bracket bra ket
  where
    bra = alloca $ \p -> ft "Init_FreeType" (ft_Init_FreeType p) >> peek p
    ket = ft "Done_FreeType" . ft_Done_FreeType

getCharIndex :: FT_Face -> Char -> IO (Maybe FT_UInt)
getCharIndex f c =
  (\case
    0 -> Nothing
    i -> Just i) <$> ft_Get_Char_Index f (fromIntegral $ ord c)
