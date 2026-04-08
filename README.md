# hledger-installments

Command-line tool for recording installment purchases in [hledger](https://hledger.org/).

## What it does

Generates journal entries for credit card installment purchases, including:

- The initial purchase transaction
- A monthly recurrence rule (`~`) for each installment debiting the card

## Installation

### Dependencies

- [stack](https://docs.haskellstack.org/) (Haskell build tool)
- [hledger](https://hledger.org/) installed and configured

### Install to `~/.local/bin`

```bash
git clone <repo>
cd hledger-installments
make install
```

### Other commands

| Command | Description |
|---------|-------------|
| `make install` | Copies script to `~/.local/bin/hledger-parcela` |
| `make uninstall` | Removes the script from `~/.local/bin` |

## Configuration

By default, entries are saved to the journal configured in hledger. To use a different file:

```bash
export LEDGER_FILE=/path/to/your/file.journal
```

## Usage

```bash
hledger parcela DESCRICAO VALOR_TOTAL N_PARCELAS CONTA_CARTAO [CATEGORIA]
hledger parcela DESCRICAO VALOR_TOTAL N_PARCELAS CONTA_CARTAO [CATEGORIA] --parcela-atual N
```

Examples:

```bash
hledger parcela "iPhone 17" 5207.90 12 liabilities:cartao:c6:carbon expenses:tech
hledger parcela "Curso Haskell" 1200.00 6 liabilities:cartao:nubank:ultravioleta
hledger parcela "RAM" 363.32 12 liabilities:cartao:c6:carbon expenses:tech --parcela-atual 9
```

The following entries are added to the journal:

```
2026-03-20 Oculos novos
    expenses:saude:otica               R$ 900.00
    liabilities:parcelado:oculos-novos

~ monthly from 2026-04-01 to 2026-07-01  Oculos novos parcela
    liabilities:parcelado:oculos-novos  R$ 300.00
    liabilities:cartao:nubank:ultravioleta
```

## Details

- Installment rounding is handled automatically (difference applied to the last installment)
- Installments start the month after the purchase
- Accepts comma or period as decimal separator
- Shows a preview of entries before saving

## Dependencies

- [hledger](https://hledger.org/) installed and configured
- [stack](https://docs.haskellstack.org/) to run the script
