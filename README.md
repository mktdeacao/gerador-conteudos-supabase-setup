# Supabase Setup — Gerador de Conteúdos

Arquivos SQL consolidados para configurar o banco do BASE Content Studio / Gerador de Conteúdos.

## Execução recomendada

No Supabase, abra SQL Editor e execute nesta ordem:

1. `SUPABASE_SETUP_PARTES/01_SUPABASE_SETUP.sql`
2. `SUPABASE_SETUP_PARTES/02_SUPABASE_SETUP.sql`
3. `SUPABASE_SETUP_PARTES/03_SUPABASE_SETUP.sql`
4. `SUPABASE_SETUP_PARTES/04_SUPABASE_SETUP.sql`
5. `SUPABASE_SETUP_PARTES/05_SUPABASE_SETUP.sql`

Se a parte 2 já tiver parado no erro da coluna `categoria`, use:

1. `SUPABASE_HOTFIX_BLOG.sql`
2. `SUPABASE_SETUP_02_CONTINUACAO.sql`
3. Partes 03, 04 e 05

O arquivo `SUPABASE_SETUP.sql` contém o bundle completo para uma instalação nova, mas as partes menores são recomendadas para evitar truncamento ao copiar e colar no SQL Editor.

## Segurança

Este repositório contém somente schema, migrations e instruções. Não contém `.env.local`, chaves de API, senhas ou connection strings.
