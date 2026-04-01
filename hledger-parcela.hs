#!/usr/bin/env stack
-- stack script --snapshot lts-22.39 --verbosity=error --package hledger --package time --package text --extra-dep hashtables-1.3.4
{-# LANGUAGE OverloadedStrings #-}
{-
hledger-parcela - registra compras parceladas no journal

Uso:
  hledger parcela DESCRICAO VALOR_TOTAL N_PARCELAS CONTA_CARTAO [CATEGORIA]
  hledger parcela DESCRICAO VALOR_TOTAL N_PARCELAS CONTA_CARTAO [CATEGORIA] --parcela-atual N

Exemplos:
  hledger parcela "iPhone 17" 5207.90 12 liabilities:cartao:c6:carbon expenses:tech
  hledger parcela "Curso Haskell" 1200.00 6 liabilities:cartao:nubank:ultravioleta
  hledger parcela "RAM" 363.32 12 liabilities:cartao:c6:carbon expenses:tech --parcela-atual 9
-}

import Hledger.Cli.Script
import Data.Text          qualified as T
import Data.Text.IO       qualified as TIO
import Data.Time
import Data.List          (isPrefixOf)
import System.IO          (hPutStrLn, stderr)
import Text.Printf        (printf)

-- ===========================================================================
-- Definição do comando
-- ===========================================================================

cmdmode = hledgerCommandMode
  (unlines
    [ "parcela"
    , "Registra uma compra parcelada no journal."
    , ""
    , "Uso:"
    , "  hledger-parcela DESCRICAO VALOR N CONTA [CATEGORIA]"
    , "  hledger-parcela DESCRICAO VALOR N CONTA [CATEGORIA] --parcela-atual P"
    , ""
    , "Argumentos:"
    , "  DESCRICAO    Nome da compra (use aspas se tiver espaços)"
    , "  VALOR        Valor total (use ponto como decimal, ex: 1200.00)"
    , "  N            Número de parcelas"
    , "  CONTA        Conta do cartão (ex: liabilities:cartao:c6:carbon)"
    , "  CATEGORIA    Conta de despesa (padrão: expenses:geral)"
    , ""
    , "Flags:"
    , "  --parcela-atual P   Parcela já paga hoje (padrão: 1)"
    , "  --data DATA         Data da compra no formato YYYY-MM-DD (padrão: hoje)"
    , ""
    , "Exemplos:"
    , "  hledger-parcela 'iPhone 17' 5207.90 12 liabilities:cartao:c6:carbon expenses:tech"
    , "  hledger-parcela 'Curso' 1200.00 6 liabilities:cartao:nubank:ultravioleta"
    , "  hledger-parcela 'RAM' 363.32 12 liabilities:cartao:c6:carbon expenses:tech --parcela-atual 9"
    ])
  [ flagReq  ["parcela-atual"] (\v o -> Right o{rawopts_= setopt "parcela-atual" v (rawopts_ o)}) "N" "parcela já paga hoje (padrão: 1)"
  , flagReq  ["data"]          (\v o -> Right o{rawopts_= setopt "data-compra"   v (rawopts_ o)}) "DATA" "data da compra YYYY-MM-DD (padrão: hoje)"
  ]
  [generalflagsgroup1]
  []
  ([], Just $ argsFlag "DESCRICAO VALOR N CONTA [CATEGORIA]")

-- ===========================================================================
-- Main
-- ===========================================================================

main :: IO ()
main = do
  opts <- getHledgerCliOpts cmdmode

  let args          = listofstringopt "args" (rawopts_ opts)
      parcelaAtual  = read $ stringopt "parcela-atual" "1" (rawopts_ opts) :: Int
      dataOpt       = stringopt "data-compra" "" (rawopts_ opts)

  hoje <- utctDay <$> getCurrentTime

  let dataCompra = case dataOpt of
        "" -> hoje
        s  -> parseTimeOrError True defaultTimeLocale "%Y-%m-%d" s

  case args of
    (desc:valorStr:nStr:conta:resto) -> do
      let categoria    = if null resto then "expenses:geral" else head resto
          valor        = read valorStr :: Double
          n            = read nStr :: Int
          slug         = map (\c -> if c == ' ' then '-' else c) (map toLower' desc)
          valorParcela = roundCents (valor / fromIntegral n)
          -- ajusta última parcela para fechar o total exato
          valorUltima  = roundCents (valor - valorParcela * fromIntegral (n - 1))

      -- validações
      if valor <= 0
        then erro "VALOR deve ser positivo."
        else if n <= 0
          then erro "N deve ser positivo."
          else if parcelaAtual < 1 || parcelaAtual > n
            then erro $ "--parcela-atual deve estar entre 1 e " ++ show n
            else do
              withJournal opts $ \j -> do
                let jpath      = journalFilePath j
                    japagas    = parcelaAtual        -- parcelas já registradas
                    jrestantes = n - parcelaAtual    -- parcelas futuras (periódico)
                    dataFim    = addGregorianMonthsClip (fromIntegral jrestantes) dataCompra

                putStrLn $ "\nAdicionando ao journal: " ++ jpath
                putStrLn $ "  " ++ desc ++ " — " ++ show n ++ "x de R$ " ++ fmtValor valorParcela
                putStrLn $ "  Parcela atual: " ++ show parcelaAtual ++ "/" ++ show n
                when (jrestantes > 0) $
                  putStrLn $ "  Periódico até: " ++ showGregorian dataFim
                putStrLn ""

                let bloco = gerarBloco dataCompra desc slug valor valorParcela valorUltima
                              n parcelaAtual japagas jrestantes dataFim conta categoria

                appendFile jpath bloco
                putStrLn "Feito! Entradas adicionadas:"
                putStrLn (replicate 60 '-')
                putStr bloco
                putStrLn (replicate 60 '-')

    _ -> do
      putStrLn "Uso: hledger-parcela DESCRICAO VALOR N CONTA [CATEGORIA]"
      putStrLn "     hledger-parcela --help"

-- ===========================================================================
-- Geração das entradas
-- ===========================================================================

gerarBloco :: Day -> String -> String -> Double -> Double -> Double
           -> Int -> Int -> Int -> Int -> Day -> String -> String -> String
gerarBloco dataCompra desc slug valor valorParcela valorUltima
           n parcelaAtual _japagas restantes dataFim conta categoria =
  unlines $ concat
    [ compraOriginal
    , [""]
    , parcelaHoje
    , [""]
    , if restantes > 0 then periodico else []
    ]
  where
    dataStr    = showGregorian dataCompra
    contaSlug  = "liabilities:parcelado:" ++ slug

    -- 1. transação da compra (registra o total como despesa e cria o passivo parcelado)
    compraOriginal =
      [ dataStr ++ " " ++ desc ++ " " ++ show n ++ "x"
      , "    " ++ categoria ++ replicate (pad categoria 40) ' ' ++ "R$ " ++ fmtValor valor
      , "    " ++ contaSlug ++ replicate (pad contaSlug 40) ' ' ++ "R$ -" ++ fmtValor valor
      ]

    -- 2. parcela atual (move do passivo parcelado para o cartão)
    valorAtual = if parcelaAtual == n then valorUltima else valorParcela
    parcelaHoje =
      [ dataStr ++ " " ++ desc ++ " " ++ show parcelaAtual ++ "/" ++ show n
      , "    " ++ contaSlug ++ replicate (pad contaSlug 40) ' ' ++ "R$ " ++ fmtValor valorAtual
      , "    " ++ conta
      ]

    -- 3. transação periódica para as parcelas futuras
    periodico =
      [ "~ monthly from " ++ showGregorian (addGregorianMonthsClip 1 dataCompra)
          ++ " to " ++ showGregorian dataFim
          ++ "  " ++ desc ++ " parcela"
      , "    " ++ contaSlug ++ replicate (pad contaSlug 40) ' ' ++ "R$ " ++ fmtValor valorParcela
      , "    " ++ conta
      ]

-- ===========================================================================
-- Utilitários
-- ===========================================================================

roundCents :: Double -> Double
roundCents x = fromIntegral (round (x * 100) :: Int) / 100

fmtValor :: Double -> String
fmtValor v = printf "%.2f" v

pad :: String -> Int -> Int
pad s n = max 1 (n - length s)

toLower' :: Char -> Char
toLower' c
  | c >= 'A' && c <= 'Z' = toEnum (fromEnum c + 32)
  | otherwise             = c

erro :: String -> IO ()
erro msg = hPutStrLn stderr ("Erro: " ++ msg)
