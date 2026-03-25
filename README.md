# hledger-installments

Ferramenta de linha de comando para registrar compras parceladas no [hledger](https://hledger.org/).

## O que faz

Gera entradas de journal para compras parceladas no cartão de crédito, incluindo:

- A transação inicial da compra
- Uma regra de recorrência mensal (`~`) para cada parcela debitando o cartão

## Instalação

### Compilar do fonte

```bash
git clone <repo>
cd hledger-installments
make build
```

### Instalar em `~/.local/bin`

```bash
make install
```

### Outros comandos

| Comando | Descrição |
|---------|-----------|
| `make build` | Compila em `bin/hledger-add-installments` |
| `make install` | Compila e copia para `~/.local/bin` |
| `make clean` | Remove o diretório `bin/` |

## Configuração

Por padrão, as entradas são salvas em `~/.hledger/hledger.journal`. Para usar outro arquivo:

```bash
export LEDGER_FILE=/caminho/para/seu/arquivo.journal
```

## Uso

```bash
./hledger-installments
```

O programa guia interativamente pela coleta de informações:

```
Data da compra [2026-03-25]: 2026-03-20
Descricao: Oculos novos
Categoria (expenses:...): expenses:saude:otica
Valor total (ex: 4773.00): 900.00
Numero de parcelas: 3
Cartao (liabilities:cartao:...): liabilities:cartao:nubank:ultravioleta
Nome da liability parcelada [oculos-novos]:
```

Após a confirmação, as seguintes entradas são adicionadas ao journal:

```
2026-03-20 Oculos novos
    expenses:saude:otica               R$ 900.00
    liabilities:parcelado:oculos-novos

~ monthly from 2026-04-01 to 2026-07-01  Oculos novos parcela
    liabilities:parcelado:oculos-novos  R$ 300.00
    liabilities:cartao:nubank:ultravioleta
```

## Detalhes

- O arredondamento das parcelas é tratado automaticamente (diferença aplicada na última parcela)
- As parcelas começam no mês seguinte à compra
- Aceita vírgula ou ponto como separador decimal
- Mostra preview das entradas antes de salvar

## Dependências

- [hledger](https://hledger.org/) instalado e configurado
- Go 1.21+ para compilar (sem dependências externas)
