{-# LANGUAGE NoImplicitPrelude #-}
{-# OPTIONS_HADDOCK hide #-}

-- | This module defines the delta renderer's default policies.

module Imj.Graphics.Render.Delta.DefaultPolicies
           where

import           Imj.Prelude

import           System.IO(BufferMode(..))

import           Imj.Graphics.Color
import           Imj.Graphics.Render.Delta.Types


-- | @=@ 'MatchTerminalSize'
defaultResizePolicy :: ResizePolicy
defaultResizePolicy = MatchTerminalSize

-- | @=@ 'ClearAtEveryFrame'
defaultClearPolicy :: ClearPolicy
defaultClearPolicy = ClearAtEveryFrame

-- | @=@ 'black'
defaultClearColor :: Color8 Background
defaultClearColor = black

-- | @=@ 'BlockBuffering' $ 'Just' 'maxBound'
defaultStdoutMode :: BufferMode
defaultStdoutMode =
  BlockBuffering $ Just maxBound -- maximize the buffer size to avoid screen tearing
