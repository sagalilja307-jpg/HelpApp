**Domän × Operationer**

| Domän | Operationer |
|---|---|
| calendar | count, list, exists, sum, latest |
| reminders | count, list, exists, sum, latest |
| mail | count, list, exists, sum, latest |
| notes | count, list, exists, sum, latest |
| files | count, list, exists, sum, latest |
| photos | count, list, exists, sum, latest |
| contacts | count, list, exists, sum, latest |
| location | count, list, exists, sum, latest |
| memory | count, list, exists, sum, latest |

**Tidsvärden**

Följande tidstyper används i `time`-kolumnen (i CSV):

- `all`
- `today`
- `today_morning`
- `today_day`
- `today_afternoon`
- `today_evening`
- `tomorrow_morning`
- `7d`
- `30d`
- `3m`
- `1y`

Den fullständiga kombinationen (domän × operation × tid) finns i CSV-filen:

[backend/docs/domain_operation_table.csv](domain_operation_table.csv)

Filen genererades automatiskt och bygger på `backend/src/helpershelp/query/intent_plan.py`.
