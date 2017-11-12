{-# LANGUAGE LambdaCase #-}

module Lib
    ( run
    ) where


import           Control.Applicative( (<|>) )
import           Control.Concurrent( threadDelay )
import           Control.Exception( finally )
import           Control.Monad( forever )
import           Control.Monad.Loops( unfoldM_ )
import           Data.Char( intToDigit )
import           Data.List( partition )
import           Data.Maybe( fromMaybe
                           , isJust
                           , isNothing
                           , maybe )
import           Data.Time( UTCTime
                          , diffUTCTime
                          , getCurrentTime )
import           System.Console.ANSI( clearScreen
                                    , setSGR
                                    , SGR(..)
                                    , ConsoleLayer(..)
                                    , ColorIntensity(..)
                                    , Color(..) )
import           System.IO( getChar
                          , hFlush
                          , hReady
                          , stdin
                          , stdout )
import           System.Timeout( timeout )


import           Console( configureConsoleFor
                        , ConsoleConfig(..)
                        , renderChar_
                        , renderSegment
                        , renderStrLn
                        , RenderState(..) )
import           Geo( sumCoords
                    , Col(..)
                    , Coords(..)
                    , coordsForDirection
                    , Direction(..)
                    , PosSpeed(..)
                    , Row(..)
                    , segmentContains
                    , translateCoord
                    , zeroCoords )
import           Laser( LaserType(..)
                      , laserChar
                      , Ray(..)
                      , Theoretical
                      , Actual
                      , shootLaserFromShip
                      , stopRayAtFirstCollision )
import           Threading( runAndWaitForTermination
                          , Termination(..) )
import           Timing( addMotionStepDuration
                       , computeTime
                       , nextUpdateCounter
                       , showUpdateTick
                       , Timer(..) )
import           Util( showListOrSingleton )
import           World( Action(..)
                      , ActionTarget(..)
                      , actionFromChar
                      , BattleShip(..)
                      , Location(..)
                      , location
                      , moveWorld
                      , mkWorld
                      , nextWorld
                      , shipCollides
                      , Step(..)
                      , World(..)
                      , Number(..)
                      , WorldSize(..) )


--------------------------------------------------------------------------------
-- Pure
--------------------------------------------------------------------------------

data GameState = GameState {
    _startTime :: !Timer
  , _nextMotionStep :: !UTCTime
  , _updateCounter :: !Int
  , _upperLeftCorner :: !Coords
  , _world :: !World
  , _gameStateLaserRay :: !(Maybe (LaserRay Actual))
  , _gameShotNumbers :: ![Int]
  , _gameTarget :: !Int
  , _gameLevel :: !Int
}

data GameStops = Lost String
               | Won

data LaserRay a = LaserRay {
    _laserRayDir :: !Direction
  , _laserRaySeg :: !(Ray a)
}

data LaserPolicy = RayDestroysFirst | RayDestroysAll

nextGameState :: GameState -> Action -> GameState
nextGameState (GameState a b c d world@(World balls _ (BattleShip (PosSpeed shipCoords _) ammo _) sz) _ g h i) action =
  let (maybeLaserRayTheoretical, newAmmo) = if ammo > 0 then case action of
          (Action Laser dir) -> (LaserRay dir <$> shootLaserFromShip shipCoords dir Infinite sz, pred ammo)
          _     -> (Nothing, ammo)
        else (Nothing, ammo)
      ((remainingBalls, destroyedBalls), maybeLaserRay) = maybe ((balls,[]), Nothing) (survivingNumbers balls RayDestroysFirst) maybeLaserRayTheoretical
      destroyedNumbers = map (\(Number _ n) -> n) destroyedBalls
      allShotNumbers = g ++ destroyedNumbers
  in GameState a b c d (nextWorld action world remainingBalls newAmmo) maybeLaserRay allShotNumbers h i

computeStop :: GameState -> Action -> Maybe GameStops
computeStop (GameState _ _ _ _ world@(World _ _ (BattleShip _ ammo safeTime) _) _ allShots target _) lastAction =
    checkShipCollision <|> checkSum <|> checkAmmo
  where
    checkShipCollision = case lastAction of
      (Timeout WorldStep) ->
        if isJust safeTime then Nothing
          else case map (\(Number _ n) -> n) $ shipCollides world of
            [] -> Nothing
            l  -> Just $ Lost $ "ship collides with " ++ showListOrSingleton l
      _ -> Nothing

    sumNumbers = sum allShots
    checkSum = case compare sumNumbers target of
      LT -> Nothing
      EQ -> Just Won
      GT -> Just $ Lost $ "sum " ++ show sumNumbers ++ " is bigger than target " ++ show target
    checkAmmo
      | ammo <= 0 = Just $ Lost "no ammo left"
      | otherwise = Nothing

survivingNumbers :: [Number] -> LaserPolicy -> LaserRay Theoretical -> (([Number],[Number]), Maybe (LaserRay Actual))
survivingNumbers l policy (LaserRay dir theoreticalRay@(Ray seg)) = case policy of
  RayDestroysAll   -> (partition (\(Number (PosSpeed pos _) _) -> (isNothing $ segmentContains pos seg)) l, justFull)
  RayDestroysFirst ->
    let (rayActual, mayCoord) = stopRayAtFirstCollision (map (\(Number (PosSpeed pos _) _) -> pos) l) theoreticalRay
        remainingNumbers = case mayCoord of
          Nothing -> (l,[])
          (Just pos') -> partition (\(Number (PosSpeed pos _) _) -> pos /= pos') l
    in (remainingNumbers, Just $ LaserRay dir rayActual)
 where
   justFull = Just $ LaserRay dir $ Ray seg

showTimer :: UTCTime -> GameState -> String
showTimer currentTime (GameState startTime _ updateTick _ (World _ _ _ worldSize) _ _ _ _) =
  let time = computeTime startTime currentTime
  in "|" ++ showUpdateTick updateTick worldSize ++ "| " ++ show time ++ " |"

--------------------------------------------------------------------------------
-- IO
--------------------------------------------------------------------------------

run :: IO Termination
run =
  (configureConsoleFor Gaming >> runAndWaitForTermination gameWorker)
  -- When Ctrl+C is hit, an exception is thrown on the main thread, hence
  -- I use 'finally' to reset the console settings.
  `finally`
   configureConsoleFor Editing


gameWorker :: IO ()
gameWorker = makeInitialState 1 >>= loop


makeInitialState :: Int -> IO GameState
makeInitialState level = do
  t <- getCurrentTime
  let nums = [1..(3+level)]
      sz = WorldSize $ 35 + 2 * (1-level)
  world <- mkWorld sz nums
  return $ GameState (Timer t) t 0 zeroCoords world Nothing [] (sum nums `quot` 2) level


loop :: GameState -> IO ()
loop state@(GameState _ _ _ coords _ _ _ _ _) = do
  let r = RenderState coords
  updateGame state r >>= loop


printTimer :: GameState -> RenderState -> IO RenderState
printTimer s r = do
  t <- getCurrentTime
  renderStrLn (showTimer t s) r


updateGame :: GameState -> RenderState -> IO GameState
updateGame state@(GameState a b c d world@(World _ _ _ sz) f g h i) r =
  getAction state >>=
    (\action -> case action of
      Nonsense -> return state
      _        -> updateGame2 action r =<<
        (case action of
          (Timeout WorldStep) ->
            getCurrentTime >>= (\t ->
              return $ GameState a (addMotionStepDuration t) (nextUpdateCounter sz c) d (moveWorld t world) f g h i)
          (Action Frame dir) ->
            return $ GameState a b c (sumCoords d $ coordsForDirection dir) world f g h i
          (Timeout AnimationStep) -> return state -- TODO animation
          _        -> return state
        ))

updateGame2 :: Action -> RenderState -> GameState -> IO GameState
updateGame2 a r s = do
  clearScreen
  let s2 = nextGameState s a
      shouldStop = computeStop s2 a
  renderGame s2 r
  maybeS3 <- mapM (handle s2) shouldStop
  let s3 = fromMaybe s2 maybeS3
  hFlush stdout
  return s3


handle :: GameState -> GameStops -> IO GameState
handle (GameState _ _ _ _ _ _ _ _ l) stop = do
  let color = case stop of
        (Lost _) -> Yellow
        Won      -> Green
  setSGR [SetColor Foreground Vivid color]
  putStrLn $ case stop of
    (Lost reason) -> " You Lose (" ++ reason ++ ")"
    Won           -> " You Win!! Congratulations."
  let level = case stop of
        (Lost _) -> 1
        Won      -> succ l
  hFlush stdout -- write previous messages
  threadDelay $ 2 * 1000000
  if level == 13
    then forever (do
      putStrLn "You reached the end of the game, your skills are really impressive! Now you can hit Ctrl + C to quit!"
      hFlush stdout
      threadDelay 1000000)
    else do
      let action = case stop of
                        (Lost _) -> "restart"
                        Won      -> "go to next level"
      putStrLn $ "Press a key to " ++ action ++ " ..."
  setSGR [SetColor Foreground Vivid White]
  unfoldM_ readOneChar -- flush inputs
  hFlush stdout        -- write previous message
  _ <- getChar         -- wait for a key press
  makeInitialState level

readOneChar :: IO (Maybe Char)
readOneChar = do
  hasMore <- hReady stdin
  if hasMore
    then do
      c <- getChar
      return $ Just c
    else
      return Nothing

{--
getActions :: IO [Action]
getActions = do
  inputs <- unfoldM readOneChar
  return $ map actionFromChar inputs
--}


getAction :: GameState -> IO Action
getAction (GameState _ nextMotionStep _ _ _ _ _ _ _) = do -- TODO animation : add an animation list, each animation contains time of next animation step
  t <- getCurrentTime
  let remainingSeconds = diffUTCTime nextMotionStep t
      remainingMicros = floor (remainingSeconds * 10^(6 :: Int))
  if remainingMicros < 0
    then return $ Timeout WorldStep
    else
      (\case
        Nothing   -> Timeout WorldStep
        Just mayChar -> case mayChar of
          (Just char) -> actionFromChar char
          Nothing     -> Nonsense
        ) <$> timeout remainingMicros readOneChar


renderGame :: GameState -> RenderState -> IO ()
renderGame state@(GameState _ _ _ _
                   (World balls _ (BattleShip (PosSpeed shipCoords _) ammo safeTime) sz)
                   maybeLaserRay shotNumbers target level)
           frameCorner = do
  _ <- printTimer state frameCorner >>= (\r -> do
    _ <- rightColumn sz r >>= renderLevel level >>= renderAmmo ammo >>= renderTarget target >>= renderShotNumbers shotNumbers
    renderWorldFrame sz r >>= (\worldCorner -> do
      _ <- case maybeLaserRay of
        (Just (LaserRay laserDir (Ray laserSeg))) -> renderSegment laserSeg (laserChar laserDir) worldCorner
        Nothing -> return worldCorner
      -- render numbers, including the ones that will be destroyed, if any
      mapM_ (\(Number (PosSpeed pos _) i) -> render_ (intToDigit i) pos sz worldCorner) balls
      let shipColor = if isNothing safeTime then Blue else Red
      setSGR [SetColor Foreground Vivid shipColor]
      render_ '+' shipCoords sz worldCorner
      setSGR [SetColor Foreground Vivid White]))

  return ()


renderShotNumbers :: [Int] -> RenderState -> IO RenderState
renderShotNumbers nums =
  renderStrLn ("Shot: " ++ show nums)

renderTarget :: Int -> RenderState -> IO RenderState
renderTarget n =
  renderStrLn ("Target: " ++ show n)


rightColumn :: WorldSize -> RenderState -> IO RenderState
rightColumn (WorldSize worldSize) (RenderState upperLeftCoords) = do
  let vmargin = 1
      hmargin = 1
      translate = Coords (Row vmargin) (Col $ worldSize + 2 + hmargin)
      corner = sumCoords upperLeftCoords translate
  return $ RenderState corner

renderLevel :: Int -> RenderState -> IO RenderState
renderLevel l =
  renderStrLn ("Level " ++ show l)

renderAmmo :: Int -> RenderState -> IO RenderState
renderAmmo ammo =
  renderStrLn ("Ammo: " ++ show ammo)

renderWorldFrame :: WorldSize -> RenderState -> IO RenderState
renderWorldFrame (WorldSize worldSize) upperLeft@(RenderState upperLeftCoords) = do
  let horizontalWall = replicate (worldSize + 2)
      lowerLeft = RenderState $ sumCoords upperLeftCoords $ Coords (Row $ worldSize+1) (Col 0)

  -- upper wall
  (RenderState renderCoords) <- renderStrLn (horizontalWall '_') upperLeft
  let worldCoords = translateCoord RIGHT renderCoords

  -- left & right walls
  let leftWallCoords = take worldSize $ iterate (translateCoord Down) renderCoords
      toRight = Coords (Row 0) (Col $ worldSize+1)
      rightWallCoords = take worldSize $ iterate (translateCoord Down) $ sumCoords renderCoords toRight
  mapM_ (renderChar_ '|' . RenderState) (leftWallCoords ++ rightWallCoords)

  -- lower wall
  _ <- renderStrLn (horizontalWall 'T') lowerLeft
  return $ RenderState worldCoords


render_ :: Char -> Coords -> WorldSize -> RenderState -> IO ()
render_ char worldCoords worldSize (RenderState renderCoords) =
  case location worldCoords worldSize of
    InsideWorld -> renderChar_ char loc
    _           -> return ()
  where loc = RenderState $ sumCoords renderCoords worldCoords
