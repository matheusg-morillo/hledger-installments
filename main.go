package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"time"
)

const dateFormat = "2006-01-02"

type purchase struct {
	date          string
	description   string
	category      string
	amount        float64
	installments  int
	card          string
	liabilityName string
}

type installmentPlan struct {
	monthly  float64
	rounding float64
	fromDate time.Time
	toDate   time.Time
}

func main() {
	journalFile := resolveJournalFile()

	fmt.Println("hledger-parcela - registro de compras parceladas")
	fmt.Println("================================================")
	fmt.Println()

	reader := bufio.NewReader(os.Stdin)
	p := collectPurchaseInfo(reader)
	plan := calculatePlan(p)

	output := buildJournalEntry(p, plan)
	printPreview(output, p, plan)

	confirm := prompt(reader, "Salvar no journal? [s/N]")
	if strings.ToLower(confirm) != "s" {
		fmt.Println("Cancelado.")
		os.Exit(0)
	}

	saveToJournal(journalFile, output)
	fmt.Printf("\nSalvo em %s\n", journalFile)
}

func resolveJournalFile() string {
	if path := os.Getenv("LEDGER_FILE"); path != "" {
		return path
	}
	home, err := os.UserHomeDir()
	if err != nil {
		die("nao foi possivel determinar o diretorio home: %v", err)
	}
	return home + "/.hledger/hledger.journal"
}

func collectPurchaseInfo(reader *bufio.Reader) purchase {
	today := time.Now().Format(dateFormat)
	date := prompt(reader, fmt.Sprintf("Data da compra [%s]", today))
	if date == "" {
		date = today
	}
	if _, err := time.Parse(dateFormat, date); err != nil {
		die("data invalida. Use o formato YYYY-MM-DD")
	}

	description := prompt(reader, "Descricao")
	if description == "" {
		die("descricao nao pode ser vazia")
	}

	fmt.Println()
	fmt.Println("Categorias comuns:")
	fmt.Println("  expenses:tech")
	fmt.Println("  expenses:saude:otica")
	fmt.Println("  expenses:casa:mobilia")
	fmt.Println("  expenses:vestuario")
	fmt.Println("  expenses:pessoal")
	fmt.Println()
	category := prompt(reader, "Categoria (expenses:...)")
	if category == "" {
		die("categoria nao pode ser vazia")
	}

	amountStr := strings.ReplaceAll(prompt(reader, "Valor total (ex: 4773.00)"), ",", ".")
	amount, err := strconv.ParseFloat(amountStr, 64)
	if err != nil || amount <= 0 {
		die("valor invalido")
	}

	installmentsStr := prompt(reader, "Numero de parcelas")
	installments, err := strconv.Atoi(installmentsStr)
	if err != nil || installments <= 0 {
		die("numero de parcelas invalido")
	}

	fmt.Println()
	fmt.Println("Cartoes disponiveis:")
	fmt.Println("  liabilities:cartao:c6:carbon")
	fmt.Println("  liabilities:cartao:nubank:ultravioleta")
	fmt.Println()
	card := prompt(reader, "Cartao (liabilities:cartao:...)")
	if card == "" {
		die("cartao nao pode ser vazio")
	}

	liabilityName := slugify(description)
	if input := prompt(reader, fmt.Sprintf("Nome da liability parcelada [%s]", liabilityName)); input != "" {
		liabilityName = input
	}

	return purchase{
		date:          date,
		description:   description,
		category:      category,
		amount:        amount,
		installments:  installments,
		card:          card,
		liabilityName: "liabilities:parcelado:" + liabilityName,
	}
}

func calculatePlan(p purchase) installmentPlan {
	purchaseDate, _ := time.Parse(dateFormat, p.date)
	fromDate := time.Date(purchaseDate.Year(), purchaseDate.Month()+1, 1, 0, 0, 0, 0, time.UTC)
	toDate := fromDate.AddDate(0, p.installments, 0)
	monthly := math.Round((p.amount/float64(p.installments))*100) / 100
	rounding := math.Round((p.amount-monthly*float64(p.installments))*100) / 100
	return installmentPlan{monthly, rounding, fromDate, toDate}
}

func buildJournalEntry(p purchase, plan installmentPlan) string {
	var sb strings.Builder

	// Purchase transaction
	fmt.Fprintf(&sb, "\n%s %s\n", p.date, p.description)
	fmt.Fprintf(&sb, "    %-45s R$ %.2f\n", p.category, p.amount)
	fmt.Fprintf(&sb, "    %s\n", p.liabilityName)

	// Periodic transaction
	fmt.Fprintf(&sb, "\n~ monthly from %s to %s  %s parcela\n",
		plan.fromDate.Format(dateFormat),
		plan.toDate.Format(dateFormat),
		p.description,
	)
	fmt.Fprintf(&sb, "    %-45s R$ %.2f\n", p.liabilityName, plan.monthly)
	fmt.Fprintf(&sb, "    %s\n", p.card)

	if plan.rounding != 0 {
		fmt.Fprintf(&sb, "\n; Nota: diferenca de R$ %.2f na ultima parcela devido a arredondamento\n", plan.rounding)
	}

	return sb.String()
}

func printPreview(output string, p purchase, plan installmentPlan) {
	fmt.Println()
	fmt.Println("================================================")
	fmt.Println("Preview:")
	fmt.Println("================================================")
	fmt.Println(output)
	fmt.Printf("Parcela mensal: R$ %.2f x %d = R$ %.2f\n", plan.monthly, p.installments, plan.monthly*float64(p.installments))
	fmt.Printf("Periodo: %s ate %s (%d parcelas)\n",
		plan.fromDate.Format("2006-01"),
		plan.toDate.AddDate(0, -1, 0).Format("2006-01"),
		p.installments,
	)
	fmt.Println()
}

func saveToJournal(journalFile, content string) {
	f, err := os.OpenFile(journalFile, os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		die("erro ao abrir journal %s: %v", journalFile, err)
	}
	defer f.Close()

	if _, err := f.WriteString(content); err != nil {
		die("erro ao escrever no journal: %v", err)
	}
}

func die(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "Erro: "+format+"\n", args...)
	os.Exit(1)
}

func prompt(reader *bufio.Reader, label string) string {
	fmt.Printf("%s: ", label)
	text, err := reader.ReadString('\n')
	if err != nil && text == "" {
		return ""
	}
	return strings.TrimSpace(text)
}

func slugify(s string) string {
	s = strings.ToLower(s)
	s = strings.ReplaceAll(s, " ", "-")
	var result strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' {
			result.WriteRune(r)
		}
	}
	return strings.Trim(result.String(), "-")
}
