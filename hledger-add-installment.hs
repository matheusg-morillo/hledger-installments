#!/usr/bin/env cabal
{- cabal:
build-depends: base, haskeline, time
-}
{-
hledger-parcela - records installment purchases in the journal (interactive)

Usage:
  hledger-parcela

Environment variable:
  LEDGER_FILE   Journal file path (default: ~/.hledger.journal)
-}

import Data.Char          (toLower, isAlphaNum)
import Data.List          (isPrefixOf, nub, sort)
import Data.Time
import System.Environment (lookupEnv)
import System.Exit        (exitSuccess, exitFailure)
import System.IO          (hPutStrLn, stderr)
import System.IO.Error    (catchIOError)
import Text.Printf        (printf)
import Control.Monad.IO.Class   (liftIO)
import System.Console.Haskeline

-- ===========================================================================
-- Main
-- ===========================================================================

main :: IO ()
main = do
  today    <- utctDay <$> getCurrentTime
  jpath    <- journalPath
  accounts <- loadAccounts jpath

  let withAccounts = accountCompleter accounts

  putStrLn $ "Journal: " ++ jpath
  putStrLn ""

  purchaseDate <- askDate        noCompletion  "Purchase date"       today
  desc         <- askText        noCompletion  "Description"
  category     <- askWithDefault withAccounts  "Category"            "expenses:general"
  amount       <- askDouble      noCompletion  "Total amount"
  n            <- askInt         noCompletion  "Number of installments"
  currentInst  <- askIntDefault  noCompletion  "Current installment" 1
  account      <- askText        withAccounts  "Card account"
  let slugDefault = toSlug desc
  slug         <- askWithDefault noCompletion  "Liability name"      slugDefault

  if currentInst < 1 || currentInst > n
    then die $ "Current installment must be between 1 and " ++ show n
    else do
      let installment = roundCents (amount / fromIntegral n)
          lastInst    = roundCents (amount - installment * fromIntegral (n - 1))
          remaining   = n - currentInst
          endDate     = addGregorianMonthsClip (fromIntegral remaining) purchaseDate
          block       = generateBlock purchaseDate desc slug amount installment lastInst
                          n currentInst remaining endDate account category

      putStrLn ""
      putStrLn $ replicate 60 '-'
      putStr block
      putStrLn $ replicate 60 '-'
      putStrLn ""

      answer <- askWithDefault noCompletion "Save to journal? [Y/n]" "y"
      if map toLower answer `elem` ["y", "yes", ""]
        then appendFile jpath block >> putStrLn "Done!"
        else putStrLn "Cancelled." >> exitSuccess

-- ===========================================================================
-- Interactive prompts
-- Each function runs its own InputT so completers can differ per field.
-- ===========================================================================

settings :: CompletionFunc IO -> Settings IO
settings comp = (defaultSettings :: Settings IO) { complete = comp, historyFile = Nothing }

askText :: CompletionFunc IO -> String -> IO String
askText comp label = runInputT (settings comp) $ do
  r <- getInputLine (label ++ ": ")
  case r of
    Nothing -> liftIO exitSuccess
    Just "" -> outputStrLn "  (required)" >> liftIO (askText comp label)
    Just v  -> return v

askWithDefault :: CompletionFunc IO -> String -> String -> IO String
askWithDefault comp label def = runInputT (settings comp) $ do
  r <- getInputLine (label ++ " [" ++ def ++ "]: ")
  case r of
    Nothing -> liftIO exitSuccess
    Just "" -> return def
    Just v  -> return v

askDate :: CompletionFunc IO -> String -> Day -> IO Day
askDate comp label today = runInputT (settings comp) $ do
  r <- getInputLine (label ++ " [" ++ showGregorian today ++ "]: ")
  case r of
    Nothing -> liftIO exitSuccess
    Just "" -> return today
    Just v  -> case parseTimeM True defaultTimeLocale "%Y-%m-%d" v of
      Just d  -> return d
      Nothing -> outputStrLn "  (invalid format, use YYYY-MM-DD)"
                   >> liftIO (askDate comp label today)

askDouble :: CompletionFunc IO -> String -> IO Double
askDouble comp label = runInputT (settings comp) $ do
  r <- getInputLine (label ++ ": ")
  case r of
    Nothing -> liftIO exitSuccess
    Just v  -> case reads (map (\c -> if c == ',' then '.' else c) v) of
      [(x, "")] | x > 0 -> return x
      _                  -> outputStrLn "  (invalid amount)" >> liftIO (askDouble comp label)

askInt :: CompletionFunc IO -> String -> IO Int
askInt comp label = runInputT (settings comp) $ do
  r <- getInputLine (label ++ ": ")
  case r of
    Nothing -> liftIO exitSuccess
    Just v  -> case reads v of
      [(x, "")] | x > 0 -> return x
      _                  -> outputStrLn "  (invalid number)" >> liftIO (askInt comp label)

askIntDefault :: CompletionFunc IO -> String -> Int -> IO Int
askIntDefault comp label def = runInputT (settings comp) $ do
  r <- getInputLine (label ++ " [" ++ show def ++ "]: ")
  case r of
    Nothing -> liftIO exitSuccess
    Just "" -> return def
    Just v  -> case reads v of
      [(x, "")] | x > 0 -> return x
      _                  -> outputStrLn "  (invalid number)"
                              >> liftIO (askIntDefault comp label def)

-- ===========================================================================
-- Account completion
-- ===========================================================================

accountCompleter :: [String] -> CompletionFunc IO
accountCompleter accounts = completeWord Nothing " \t" $ \prefix ->
  return [ simpleCompletion a | a <- accounts, prefix `isPrefixOf` a ]

loadAccounts :: FilePath -> IO [String]
loadAccounts path = do
  contents <- catchIOError (readFile path) (const $ return "")
  let accs = filter looksLikeAccount
           . map (takeWhile (not . (== ' ')) . dropWhile (== ' '))
           . filter (not . null)
           . map (dropWhile (== ' '))
           $ lines contents
  return $ sort $ nub accs

looksLikeAccount :: String -> Bool
looksLikeAccount s = ':' `elem` s && not (null s)
                  && all (\c -> isAlphaNum c || c `elem` ":-_") s

-- ===========================================================================
-- Entry generation
-- ===========================================================================

generateBlock :: Day -> String -> String -> Double -> Double -> Double
              -> Int -> Int -> Int -> Day -> String -> String -> String
generateBlock purchaseDate desc slug amount installment lastInst
              n currentInst remaining endDate account category =
  unlines $ concat
    [ purchase
    , [""]
    , currentPayment
    , [""]
    , if remaining > 0 then periodic else []
    ]
  where
    dateStr     = showGregorian purchaseDate
    liabAccount = "liabilities:installments:" ++ slug

    purchase =
      [ dateStr ++ " " ++ desc ++ " " ++ show n ++ "x"
      , "    " ++ category    ++ replicate (pad category    40) ' ' ++ "R$ " ++ fmt amount
      , "    " ++ liabAccount ++ replicate (pad liabAccount 40) ' ' ++ "R$ -" ++ fmt amount
      ]

    currentAmount = if currentInst == n then lastInst else installment
    currentPayment =
      [ dateStr ++ " " ++ desc ++ " " ++ show currentInst ++ "/" ++ show n
      , "    " ++ liabAccount ++ replicate (pad liabAccount 40) ' ' ++ "R$ " ++ fmt currentAmount
      , "    " ++ account
      ]

    periodic =
      [ "~ monthly from " ++ showGregorian (addGregorianMonthsClip 1 purchaseDate)
          ++ " to " ++ showGregorian endDate
          ++ "  " ++ desc ++ " installment"
      , "    " ++ liabAccount ++ replicate (pad liabAccount 40) ' ' ++ "R$ " ++ fmt installment
      , "    " ++ account
      ]

-- ===========================================================================
-- Utilities
-- ===========================================================================

journalPath :: IO FilePath
journalPath = do
  mEnv  <- lookupEnv "LEDGER_FILE"
  mHome <- lookupEnv "HOME"
  let expandTilde ('~':rest) = maybe "~" (++ rest) mHome
      expandTilde p           = p
  case mEnv of
    Just p  -> return (expandTilde p)
    Nothing -> case mHome of
      Just h  -> return (h ++ "/.hledger.journal")
      Nothing -> return ".hledger.journal"

toSlug :: String -> String
toSlug = map (\c -> if c == ' ' then '-' else toLower c)

roundCents :: Double -> Double
roundCents x = fromIntegral (round (x * 100) :: Int) / 100

fmt :: Double -> String
fmt v = printf "%.2f" v

pad :: String -> Int -> Int
pad s n = max 1 (n - length s)

die :: String -> IO ()
die msg = hPutStrLn stderr ("Error: " ++ msg) >> exitFailure
