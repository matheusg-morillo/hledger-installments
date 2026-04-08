# hledger-installments

Command-line tool for recording installment purchases in [hledger](https://hledger.org/).

## What it does

Interactively generates journal entries for credit card installment purchases, including:

- The initial purchase transaction
- The current installment payment
- A monthly recurrence rule (`~`) for the remaining installments

## Installation

### Dependencies

- [cabal](https://www.haskell.org/cabal/) (Haskell build tool)
- [hledger](https://hledger.org/) installed and configured

### Install to `~/.local/bin`

```bash
git clone <repo>
cd hledger-installments
make install
```

On first run, cabal will download and compile `haskeline` automatically.

### Other commands

| Command | Description |
|---------|-------------|
| `make install` | Copies script to `~/.local/bin/hledger-parcela` |
| `make uninstall` | Removes the script from `~/.local/bin` |

## Configuration

By default, entries are saved to `~/.hledger.journal`. To use a different file:

```bash
export LEDGER_FILE=/path/to/your/file.journal
```

## Usage

```bash
hledger-parcela
```

The program guides you through each field interactively, with tab completion for account names:

```
Journal: /home/user/.hledger.journal

Purchase date [2026-04-08]: 2026-03-20
Description: Oculos novos
Category [expenses:general]: expenses:health
Total amount: 900.00
Number of installments: 3
Current installment [1]:
Card account: liabilities:card:nubank
Liability name [oculos-novos]:

------------------------------------------------------------
2026-03-20 Oculos novos 3x
    expenses:health                         R$ 900.00
    liabilities:installments:oculos-novos   R$ -900.00

2026-03-20 Oculos novos 1/3
    liabilities:installments:oculos-novos   R$ 300.00
    liabilities:card:nubank

~ monthly from 2026-04-20 to 2026-05-20  Oculos novos installment
    liabilities:installments:oculos-novos   R$ 300.00
    liabilities:card:nubank
------------------------------------------------------------

Save to journal? [Y/n]:
```

## Details

- Tab completion for account names reads from your journal file
- Installment rounding is handled automatically (difference applied to the last installment)
- Accepts comma or period as decimal separator
- Shows a preview before saving
- `Current installment` allows recording a purchase mid-way through (e.g. installment 3 of 12)
