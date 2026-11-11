# Experimentos

Registro de cada mudança testada, com o antes, o depois e a conclusão.

## Como ler

- Todas as medições usam os mesmos parâmetros: `vus: 20`, `duracao: 60s`, `semente: 42` (registrados no `contexto.txt` de cada pasta).
- Cada medição foi rodada 3 vezes com o mesmo rótulo. Os valores das tabelas são a **mediana das 3 execuções**, tirada métrica por métrica dos arquivos `resumo.txt` e `recursos.txt` de cada pasta; nenhum número foi digitado fora deles.
- **p95 geral** e **req/s** vêm do `resumo.txt`; **p95 pedidos-do-cliente** vem da tabela "Por rota" do mesmo arquivo; **CPU** e **memória** são a `cpu_media` e a `mem_media` do `recursos.txt` (100% = 1 CPU inteira).
- Limites dos containers em todas as medições: banco com 1 CPU e 512 MB, API com 0,5 CPU e 256 MB (sem alteração).

## Resumo

| # | Ideia | Fonte | Status | Antes | Depois | Conclusão |
|---|---|---|---|---|---|---|
| 01 | Índice em `pedidos (cliente_id, criado_em DESC, id DESC)` | Diagnóstico próprio: [`diagnostico/00-pedidos-por-cliente.txt`](diagnostico/00-pedidos-por-cliente.txt). Documentação: [preencher com o link que você abriu] | Aplicada, sem ganho claro | Controle: 2.69 req/s, p95 26751.0 ms | 2.93 req/s, p95 21497.2 ms | A consulta ficou muito mais rápida, mas o banco continuou em ~100% de CPU; a diferença na carga está dentro da variação entre execuções |

## Medições de referência

### 00 · Linha de base original

Aplicação como veio, commit `d64742f`, banco criado cerca de 20 horas antes da medição.

| Métrica | Mediana das 3 |
|---|---|
| Req/s | 3.68 |
| p95 geral | 17501.9 ms |
| p95 pedidos-do-cliente | 19517.3 ms |
| CPU banco / API | 99.4% / 9.3% |
| Memória banco / API | 398.5 MiB / 75.4 MiB |

Pastas:
[`20261111-192841`](resultados/20261111-192841-00-linha-de-base/resumo.txt) ·
[`20261111-193058`](resultados/20261111-193058-00-linha-de-base/resumo.txt) ·
[`20261111-193251`](resultados/20261111-193251-00-linha-de-base/resumo.txt)

Observação: o banco ficou entre 96.8% e 99.8% de CPU nas 3 execuções, e a API entre 9.1% e 10.7%. O gargalo é o banco.

### 00 · Controle: linha de base com banco recriado

Mesmo código da linha de base, sem índice novo (commit `475b561`), mas com o banco recriado do zero (`docker compose down -v && docker compose up -d --build`), como acontece ao aplicar qualquer `.sql` novo.

**Por que existe:** a mudança 01 pareceu piorar a aplicação. Como aplicar a 01 exigiu recriar o banco, havia duas explicações possíveis: o índice ou o banco recriado. O controle mede o código sem o índice nas mesmas condições da 01.

| Métrica | Mediana das 3 |
|---|---|
| Req/s | 2.69 |
| p95 geral | 26751.0 ms |
| p95 pedidos-do-cliente | 30170.6 ms |
| CPU banco / API | 99.0% / 7.9% |
| Memória banco / API | 382.5 MiB / 30.3 MiB |

Pastas:
[`20261111-202351`](resultados/20261111-202351-00-linha-de-base-banco-recriado/resumo.txt) ·
[`20261111-202531`](resultados/20261111-202531-00-linha-de-base-banco-recriado/resumo.txt) ·
[`20261111-202714`](resultados/20261111-202714-00-linha-de-base-banco-recriado/resumo.txt)

**Conclusão:** o mesmo código ficou mais lento que na linha de base original (2.69 contra 3.68 req/s). A piora vista na 01 não foi causada pelo índice.

**O que não está explicado:** o controle não separa duas causas possíveis para essa diferença: (a) o banco recém-recriado ser mais lento ou (b) a máquina ter ficado mais lenta ao longo da noite. As medições foram feitas nesta ordem: linha de base às 19:28, 01 às 19:55 e 20:06, controle às 20:23.

**Decisão:** a partir daqui, o "antes" de cada mudança é o **controle**, e não a linha de base original, porque ele foi medido nas mesmas condições das mudanças que exigem recriar o banco.

## Mudanças

### 01 · Índice em `pedidos (cliente_id, criado_em DESC, id DESC)`

- **Hipótese** (registrada depois da mudança): criar um índice em `pedidos (cliente_id, criado_em DESC, id DESC)` deve reduzir o p95 da rota `pedidos-do-cliente`, porque a consulta dos pedidos de um cliente deixa de percorrer os 500 mil pedidos e de ordenar o resultado.
- **Mudança:** [`banco/03-indice-pedidos-cliente.sql`](banco/03-indice-pedidos-cliente.sql), commit `ae491fa`.
- **Fonte:** diagnóstico próprio; documentação: [preencher com o link que você abriu].
- **Antes:** controle (banco recriado, sem índice).

**Diagnóstico da consulta** (`EXPLAIN ANALYZE` com o banco sem carga):

| | Antes | Depois |
|---|---|---|
| Arquivo | [`diagnostico/00-pedidos-por-cliente.txt`](diagnostico/00-pedidos-por-cliente.txt) | [`diagnostico/01-pedidos-por-cliente.txt`](diagnostico/01-pedidos-por-cliente.txt) |
| Plano | `Parallel Seq Scan on pedidos` + `Sort` | `Index Scan using idx_pedidos_cliente_data` |
| Execution Time | 202.952 ms | 0.059 ms |

**Carga:**

| Métrica | Antes (controle) | Depois (01) |
|---|---|---|
| Req/s | 2.69 | 2.93 |
| p95 geral | 26751.0 ms | 21497.2 ms |
| p95 pedidos-do-cliente | 30170.6 ms | 25979.5 ms |
| CPU banco / API | 99.0% / 7.9% | 98.2% / 7.5% |
| Memória banco / API | 382.5 MiB / 30.3 MiB | 391.1 MiB / 29.9 MiB |

Pastas do depois:
[`20261111-200605`](resultados/20261111-200605-01-indice-pedidos-cliente/resumo.txt) ·
[`20261111-200840`](resultados/20261111-200840-01-indice-pedidos-cliente/resumo.txt) ·
[`20261111-201023`](resultados/20261111-201023-01-indice-pedidos-cliente/resumo.txt)

**Conclusão: aplicada, sem ganho claro.** O índice funciona: a consulta de pedidos do cliente passou de 202.952 ms para 0.059 ms. Mas o banco continuou em ~100% de CPU, e a melhora na carga (2.69 para 2.93 req/s) é pequena perto da variação entre execuções. Explicação provável, a partir do código: na rota `/clientes/:id/pedidos`, a consulta de `pedidos` roda uma vez por requisição, enquanto a de `itens_pedido` (1,5 milhão de linhas, sem índice em `pedido_id`) roda uma vez para cada pedido do cliente, e continua lendo a tabela inteira ([`diagnostico/00-itens-por-pedido.txt`](diagnostico/00-itens-por-pedido.txt)). As outras rotas lentas também continuam lendo tabelas inteiras.

**Medições descartadas:** as 3 primeiras medições da 01 foram feitas com o arquivo `diagnostico/01-pedidos-por-cliente.txt` ainda sem commit (`contexto.txt` registra `commit: ae491fa` e `arquivos alterados sem commit: 1`). O código medido era o mesmo, mas elas não seguem a regra do desafio e não entram na comparação. Foram mantidas no repositório por transparência (commit `42d785c`):
[`20261111-195538`](resultados/20261111-195538-01-indice-pedidos-cliente/resumo.txt) ·
[`20261111-195739`](resultados/20261111-195739-01-indice-pedidos-cliente/resumo.txt) ·
[`20261111-195927`](resultados/20261111-195927-01-indice-pedidos-cliente/resumo.txt)
