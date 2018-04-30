{-# OPTIONS_HADDOCK hide #-}

{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TypeFamilies #-}

module Imj.Game.Hamazed.KeysMaps
    ( translatePlatformEvent
    ) where

import           Imj.Prelude

import qualified Data.Map as Map(lookup)

import           Imj.Game.Hamazed.Loop.Event.Types
import           Imj.Game.Hamazed.State.Types
import           Imj.Game.Hamazed.Network.Types
import           Imj.Game.Hamazed.World.Space.Types
import           Imj.Game.Hamazed.Types
import           Imj.Input.Types
import           Imj.Client.Class

-- TODO split in 2: generic translation, specialized translation
translatePlatformEvent :: (ServerT e ~ Hamazed
                         , CliEvtT e ~ Event HamazedEvent
                         , MonadState (AppState evt) m)
                       => PlatformEvent
                       -> m (Maybe (GenEvent e))
translatePlatformEvent k = case k of
  Message msgLevel txt -> return $ Just $ Evt $ Log msgLevel txt
  StopProgram -> return $ Just $ CliEvt $ RequestApproval $ Leaves $ Right ()
  FramebufferSizeChanges -> return $ Just $ Evt RenderingTargetChanged
  KeyPress key -> case key of
    Escape      -> return $ Just $ CliEvt $ RequestApproval $ Leaves $ Right ()
    Tab -> return $ Just $ Evt $ AppEvent $ ChatCmd ToggleEditing
    _ -> getChatMode >>= \case
      Editing -> return $ case key of
        Delete     -> Just $ Evt $ AppEvent $ ChatCmd DeleteAtEditingPosition
        BackSpace  -> Just $ Evt $ AppEvent $ ChatCmd DeleteBeforeEditingPosition
        AlphaNum c -> Just $ Evt $ AppEvent $ ChatCmd $ Insert c
        Arrow dir  -> Just $ Evt $ AppEvent $ ChatCmd $ Navigate dir
        Enter      -> Just $ Evt $ AppEvent SendChatMessage
        _ -> Nothing
      NotEditing -> case key of
        {-
        KeyPress (AlphaNum '1') -> return $ Just $ Evt $ PlayProgram 1
        KeyPress (AlphaNum '2') -> return $ Just $ Evt $ PlayProgram 2
        KeyPress (AlphaNum '3') -> return $ Just $ Evt $ PlayProgram 3
        KeyPress (AlphaNum '4') -> return $ Just $ Evt $ PlayProgram 4
        KeyPress (AlphaNum '5') -> return $ Just $ Evt $ PlayProgram 5
        KeyPress (AlphaNum '6') -> return $ Just $ Evt $ PlayProgram 6
        KeyPress (AlphaNum '7') -> return $ Just $ Evt $ PlayProgram 7
        KeyPress (AlphaNum '8') -> return $ Just $ Evt $ PlayProgram 8
        KeyPress (AlphaNum '9') -> return $ Just $ Evt $ PlayProgram 9
        KeyPress (AlphaNum '0') -> return $ Just $ Evt $ PlayProgram 0
        -}
        Arrow Up    -> return $ Just $ Evt $ CycleRenderingOptions (-1) 0
        Arrow Down  -> return $ Just $ Evt $ CycleRenderingOptions 1 0
        Arrow LEFT  -> return $ Just $ Evt $ CycleRenderingOptions 0 (-1)
        Arrow RIGHT -> return $ Just $ Evt $ CycleRenderingOptions 0 1
        -- commented out, replaced by precomputed PPU / Margins associations (see 4 lines above)
        {-
        AlphaNum 'h' -> return $ Just $ Evt $ ApplyPPUDelta $ Size 1 0
        AlphaNum 'n' -> return $ Just $ Evt $ ApplyPPUDelta $ Size (-1) 0
        AlphaNum 'b' -> return $ Just $ Evt $ ApplyPPUDelta $ Size 0 (-1)
        AlphaNum 'm' -> return $ Just $ Evt $ ApplyPPUDelta $ Size 0 1
        AlphaNum 'g' -> return $ Just $ Evt $ ApplyFontMarginDelta $ -1
        AlphaNum 'v' -> return $ Just $ Evt $ ApplyFontMarginDelta 1
        -}
        _ -> do
          (ClientState activity state) <- getClientState <$> gets game
          case activity of
            Over -> return Nothing
            Ongoing -> case state of
              Excluded -> return Nothing
              Setup -> return $ case key of
                AlphaNum c -> case c of
                  ' ' -> Just $ CliEvt $ ExitedState Setup
                  '1' -> Just $ CliEvt $ Do $ Put $ WorldShape Square
                  '2' -> Just $ CliEvt $ Do $ Put $ WorldShape Rectangle'2x1
                  --'e' -> Just $ CliEvt $ Do $ Put $ WallDistribution None
                  --'r' -> Just $ CliEvt $ Do $ Put $ WallDistribution $ minRandomBlockSize 0.5
                  'y' -> Just $ CliEvt $ Do $ Succ BlockSize
                  'g' -> Just $ CliEvt $ Do $ Pred BlockSize
                  'u' -> Just $ CliEvt $ Do $ Succ WallProbability
                  'h' -> Just $ CliEvt $ Do $ Pred WallProbability
                  _ -> Nothing
                _ -> Nothing
              PlayLevel status -> case status of
                Running -> maybe
                  (case key of
                    AlphaNum c -> case c of
                      'k' -> Just $ CliEvt $ Action Laser Down
                      'i' -> Just $ CliEvt $ Action Laser Up
                      'j' -> Just $ CliEvt $ Action Laser LEFT
                      'l' -> Just $ CliEvt $ Action Laser RIGHT
                      'd' -> Just $ CliEvt $ Action Ship Down
                      'e' -> Just $ CliEvt $ Action Ship Up
                      's' -> Just $ CliEvt $ Action Ship LEFT
                      'f' -> Just $ CliEvt $ Action Ship RIGHT
                      --'r'-> Just $ Evt ToggleEventRecording
                      _   -> Nothing
                    _ -> Nothing)
                  (const Nothing)
                  <$> getLevelOutcome
                WhenAllPressedAKey _ (Just _) _ -> return Nothing
                WhenAllPressedAKey x Nothing havePressed ->
                  getMyShipId >>= maybe
                    (return Nothing)
                    (\me -> maybe (error "logic") (\iHavePressed ->
                            if iHavePressed
                              then return Nothing
                              else return $ Just $ CliEvt $ CanContinue x)
                              $ Map.lookup me havePressed)
                New -> return Nothing
                Paused _ _ -> return Nothing
                Countdown _ _ -> return Nothing
                OutcomeValidated _ -> return Nothing
                CancelledNoConnectedPlayer -> return Nothing
                WaitingForOthersToEndLevel _ -> return Nothing
