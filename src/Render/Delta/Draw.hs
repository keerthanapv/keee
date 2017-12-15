{-# OPTIONS_HADDOCK hide #-}

module Render.Delta.Draw
            ( fill
            , drawChar
            , drawChars
            , drawStr
            , drawTxt
            , module Color
            , module Geo.Discrete.Types
            , String
              -- utilities
            , fillBackBuffer
            ) where

import           Prelude hiding (length)

import           Data.IORef( IORef , readIORef )
import           Data.Text(Text, unpack)
import           Data.Vector.Unboxed.Mutable( write, set, length )

import           Color
import           Geo.Discrete.Types
import           Render.Delta.Types
import           Render.Delta.Cell
import           Render.Types


{-# INLINE drawChar #-}
-- | Draw a 'Char'
drawChar :: IORef Buffers
         -> Char
         -> Coords
         -- ^ Location
         -> LayeredColor
         -- ^ Background and foreground colors
         -> IO ()
drawChar ref c pos colors =
  readIORef ref
    >>= \(Buffers back@(Buffer b) _ width _ _) -> do
      let size = fromIntegral $ length b
      writeToBack back (indexFromPos size width pos) (mkCell colors c)


{-# INLINE drawChars #-}
-- | Draws a 'Char' multiple times, starting at the given coordinates and then moving to the right.
--
-- @drawChar n c@ should be faster than @drawStr (repeat n c)@,
-- as the encoding of information in a 'Cell' happens once only. (TODO verify in GHC core with optimizations)
drawChars :: IORef Buffers
          -> Int
          -- ^ Number of chars to draw
          -> Char
          -> Coords
          -- ^ Location of left-most 'Char'
          -> LayeredColor
          -- ^ Background and foreground colors
          -> IO ()
drawChars ref count c pos colors =
  readIORef ref
    >>= \(Buffers back@(Buffer b) _ width _ _) -> do
      let cell = mkCell colors c
          size = fromIntegral $ length b
          idx = indexFromPos size width pos
      mapM_
        (\i -> let idx' = (fromIntegral idx + i) `fastMod` size
               in writeToBack back idx' cell)
        [0..pred count]


{-# INLINE drawStr #-}
-- | Draw a 'String'
drawStr :: IORef Buffers
        -> String
        -> Coords
        -- ^ Location of first 'Char'
        -> LayeredColor
        -- ^ Background and foreground colors
        -> IO ()
drawStr ref str pos colors =
  readIORef ref
    >>= \(Buffers back@(Buffer b) _ width _ _) -> do
      let size = fromIntegral $ length b
          idx = indexFromPos size width pos
      mapM_
        (\(c, i) ->
            writeToBack back (idx+i `fastMod` size) (mkCell colors c))
        $ zip str [0..]

{-# INLINE drawTxt #-}
-- | Draw a 'Text'
drawTxt :: IORef Buffers
        -> Text
        -> Coords
        -- ^ Location of first 'Char'
        -> LayeredColor
        -- ^ Background and foreground colors
        -> IO ()
drawTxt ref text = drawStr ref $ unpack text


{-# INLINE writeToBack #-}
writeToBack :: Buffer Back -> Dim Index -> Cell -> IO ()
writeToBack (Buffer b) pos = write b (fromIntegral pos)


-- | Fills the entire area with a colored char.
fill :: Char
     -> LayeredColor
     -> IORef Buffers
     -> IO ()
fill char colors ioRefBuffers =
  readIORef ioRefBuffers
    >>= flip fillBackBuffer (mkCell colors char)


fillBackBuffer :: Buffers
               -> Cell
               -> IO ()
fillBackBuffer (Buffers (Buffer b) _ _ _ _) =
  set b


{-# INLINE indexFromPos #-}
indexFromPos :: Dim Size -> Dim Width -> Coords -> Dim Index
indexFromPos size width (Coords y x) =
  (fromIntegral y * fromIntegral width + fromIntegral x) `fastMod` size


-- | Modulo optimized for cases where most of the time,
--    a < b (for a mod b)
{-# INLINE fastMod #-}
fastMod :: Int -> Dim Size -> Dim Index
fastMod a b'
  | 0 <= a && a < b = fromIntegral a          -- fast path
  | otherwise       = fromIntegral $ a `mod` b  -- slow path
  where b = fromIntegral b'