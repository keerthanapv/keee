{-# LANGUAGE NoImplicitPrelude #-}

-- initially I needed this custom Prelude to hide putStr and putChar,
-- since I provide equivalent functions that should be used instead to
-- render the game

module Imajuscule.Prelude ( module Prelude
                          , module Control.Applicative
                          , module Control.Arrow
                          , module Control.Exception
                          , module Control.Monad
                          , module Control.Monad.IO.Class
                          , module Control.Monad.Reader
                          , module Data.Maybe
                          , module Data.Monoid
                          , module Data.Ratio
                          , module Data.Text
                          , module Data.Word
                          ) where

import           Prelude( Eq, Show(..), Real, Num, Enum, Integral, Ord, Monoid(..), Monad(..)
                        , Bool(..), Char, Float, IO, Int, Maybe(..), Either(..), Ordering(..)
                        , either, maybe
                        , sum, map, concatMap, filter, mapM, mapM_
                        , all, any, notElem, null, minimum, maximum
                        , replicate, (++), take, takeWhile, tail, last, head, drop, reverse, iterate, unwords
                        , zip, zipWith, fst, snd
                        , fmap, (.), (=<<), ($), (<$>), const, id, flip, curry, uncurry
                        , compare, not, or, (||), (&&), otherwise
                        , (*), (**), (+), (-), (/), (^), (==), (/=), (>), (<), (>=), (<=)
                        , realToFrac, fromIntegral, fromRational, recip, signum, pred, succ
                        , sin, cos, pi
                        , mod, min, max, abs, floor, ceiling, maxBound
                        , negate, div, quot, even, odd
                        , error
                        )

import           Control.Applicative((<|>))
import           Control.Arrow((>>>))
import           Control.Monad(when, void, (<=<), Monad)
import           Control.Monad.IO.Class(liftIO)
import           Control.Monad.Reader(ReaderT)
import           Control.Exception(assert)
import           Data.Maybe(listToMaybe)
import           Data.Monoid((<>))
import           Data.Word(Word8)
import           Data.Text(Text)
import           Data.Ratio((%))
