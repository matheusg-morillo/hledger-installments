# hledger-installments

Command-line tool for recording installment purchases in [hledger](https://hledger.org/).

## What it does

Generates journal entries for credit card installment purchases, including:

- The initial purchase transaction
- A monthly recurrence rule (`~`) for each installment debiting the card

## Installation

### Build from source

```bash
git clone <repo>
cd hledger-installments
make build
```

### Install to `~/.local/bin`

```bash
make install
```

### Other commands

| Command | Description |
|---------|-------------|
| `make build` | Builds to `bin/hledger-add-installments` |
| `make install` | Builds and copies to `~/.local/bin` |
| `make clean` | Removes the `bin/` directory |

## Configuration

By default, entries are saved to `~/.hledger/hledger.journal`. To use a different file:

```bash
export LEDGER_FILE=/path/to/your/file.journal
```

## Usage

```bash
./hledger-installments
```

The program interactively guides you through collecting the required information:

```
Purchase date [2026-03-25]: 2026-03-20
Description: Oculos novos
Category (expenses:...): expenses:saude:otica
Total amount (e.g. 4773.00): 900.00
Number of installments: 3
Card (liabilities:cartao:...): liabilities:cartao:nubank:ultravioleta
Installment liability name [oculos-novos]:
```

After confirmation, the following entries are added to the journal:

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
- Go 1.21+ to build (no external dependencies)
