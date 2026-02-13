# Introduction

Welcome to Offshore Budgeting, a privacy-first budgeting app. All data is processed on your device, and you will never be asked to connect a bank account. This guide introduces the core building blocks and explains exactly how totals are calculated across the app.

## The Building Blocks
Cards, Income, Expense Categories, Presets, and Budgets are the foundation:
- Cards hold your expenses and let you analyze spending by card.
- Income is tracked as planned or actual. Planned income helps you forecast savings, while actual income powers real savings calculations.
- Expense Categories describe what an expense was for, like groceries, rent, or fuel.
- Presets are reusable planned expenses for recurring bills.
- Variable expenses are one-off or unpredictable expenses tied to a card.
- Budgets group a date range so the app can summarize income, expenses, and savings for that period.

## Planned Expenses
Expected or recurring costs for a budget period, like rent or subscriptions.
- Planned Amount: the amount you expect to debit from your account.
- Actual Amount: if a planned expense costs more or less than expected, edit the planned expense and enter the actual amount.

## Variable Expenses
Unpredictable, one-off costs during a budget period, like fuel or dining. These are always treated as actual spending and are tracked by card and category.

## Planned Income
Income you expect to receive, like salary or deposits. Planned income is used for forecasts and potential savings.
- Use planned income to help plan your budget. If income is very consistent, consider recurring actual income instead.

## Actual Income
Income you actually receive. Actual income drives real totals, real savings, and the amount you can still spend safely.
- Income can be logged as actual when received, or set as recurring actual income for consistent paychecks.

## Budgets
Budgets are a lens for viewing your income and expenses over a specific date range. Create budgets that align with your financial goals and pay cycles.

## How Totals Are Calculated
Everything in Offshore is basic math:
- Planned expenses total = sum of planned amounts for planned expenses in the budget period.
- Actual planned expenses total = sum of actual amounts for those planned expenses.
- Variable expenses total = sum of variable expenses in the budget period.
- Planned income total = sum of income entries marked Planned in the period.
- Actual income total = sum of income entries marked Actual in the period.
- Potential savings = planned income total - planned expenses planned total.
- Actual savings = actual income total - (planned expenses actual total + variable expenses total).
