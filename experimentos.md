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
| 02 | Índice em `itens_pedido (pedido_id, id)` | Diagnóstico próprio: [`diagnostico/00-itens-por-pedido.txt`](diagnostico/00-itens-por-pedido.txt) | Aplicada e medida | 01: 2.93 req/s, p95 21497.2 ms | 4.85 req/s, p95 12529.4 ms | Ganho claro, acima da variação: mais requisições por segundo e p95 menor; o banco continua em ~100% de CPU, agora atendendo mais requisições |
| 03 | Índice em `pedidos (status, criado_em DESC, id DESC)` | Diagnóstico próprio: [`diagnostico/03-consultas-por-rota.txt`](diagnostico/03-consultas-por-rota.txt) | Aplicada, sem ganho claro | 02: 4.85 req/s, p95 12529.4 ms | 5.27 req/s, p95 11714.9 ms | A página ficou muito mais rápida, mas o `count(*)` quase não mudou; a diferença geral está dentro da variação entre execuções |
| 04 | Ranking de `top-produtos` pré-calculado numa visão materializada | Diagnóstico próprio: [`diagnostico/03-consultas-por-rota.txt`](diagnostico/03-consultas-por-rota.txt). Documentação: [preencher com o link que você abriu] | Aplicada e medida | 03: 5.27 req/s, p95 11714.9 ms | 7.85 req/s, p95 9635.0 ms | Maior ganho até aqui: a rota caiu de dezenas de segundos para menos de 1 s e liberou o banco para as outras rotas |
| 05 | Pool de conexões na API (`pg.Pool`) | Diagnóstico próprio: [`diagnostico/05-custo-de-conexao.txt`](diagnostico/05-custo-de-conexao.txt). Documentação: [preencher com o link que você abriu] | Aplicada e medida | 04: 7.85 req/s, p95 9635.0 ms | 21.50 req/s, p95 3282.7 ms | Maior ganho até aqui: abrir uma conexão por consulta era o principal desperdício |
| 06 | Tirar o N+1 de `pedidos-do-cliente`: itens e nomes de produto numa consulta só | Diagnóstico próprio: [`diagnostico/06-consultas-por-requisicao.txt`](diagnostico/06-consultas-por-requisicao.txt). Fonte: [preencher com o link que você abriu] | Aplicada, ganho parcial | 05: 21.50 req/s, p95 3282.7 ms | 20.88 req/s, p95 2216.3 ms | A rota ficou bem mais rápida e o p95 geral caiu, mas as req/s não mudaram: o banco continua sendo o limite |
| 07 | Total de pedidos por status pré-calculado numa visão materializada | Diagnóstico próprio: [`diagnostico/03-pedidos-por-status-depois.txt`](diagnostico/03-pedidos-por-status-depois.txt). Documentação: [preencher com o link que você abriu] | Aplicada, sem ganho | 06: 20.88 req/s, p95 2216.3 ms | 20.70 req/s, p95 2404.6 ms | Hipótese refutada: a contagem saiu do banco, mas as req/s ficaram dentro da variação da 06 |

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

### 02 · Índice em `itens_pedido (pedido_id, id)`

- **Hipótese** (registrada antes da mudança): criar um índice em `itens_pedido (pedido_id, id)` deve reduzir o p95 da rota `pedidos-do-cliente` e a CPU do banco, porque hoje cada pedido do cliente dispara uma leitura completa da tabela `itens_pedido`, com cerca de 1,5 milhão de linhas, para devolver poucos itens ([`diagnostico/00-itens-por-pedido.txt`](diagnostico/00-itens-por-pedido.txt): `Parallel Seq Scan on itens_pedido`, `Rows Removed by Filter: 499999` em cada um dos 3 processos, `Execution Time: 116.237 ms`).
- **Por que acho que esta mudança deve ter mais efeito que a 01:** na rota `/clientes/:id/pedidos`, a consulta de `pedidos` roda uma vez por requisição, mas a de `itens_pedido` roda uma vez para cada pedido do cliente. A 01 tirou a varredura que acontecia uma vez; esta tira a que se repete.
- **O que refutaria a hipótese:** o p95 de `pedidos-do-cliente` e a CPU do banco ficarem dentro da variação da 01. Nesse caso, o gargalo principal estaria em outra rota.
- **Antes:** mudança 01 (mesmas condições: banco recriado do zero).

**Diagnóstico da consulta** (`EXPLAIN ANALYZE` com o banco sem carga):

| | Antes | Depois |
|---|---|---|
| Arquivo | [`diagnostico/00-itens-por-pedido.txt`](diagnostico/00-itens-por-pedido.txt) | [`diagnostico/02-itens-por-pedido.txt`](diagnostico/02-itens-por-pedido.txt) |
| Plano | `Parallel Seq Scan on itens_pedido` + `Sort` | `Index Scan using idx_itens_pedido_pedido_id` |
| Execution Time | 116.237 ms | 0.049 ms |

- **Mudança:** [`banco/04-indice-itens-pedido.sql`](banco/04-indice-itens-pedido.sql), commit `8507550`.

**Carga:**

| Métrica | Antes (01) | Depois (02) |
|---|---|---|
| Req/s | 2.93 | 4.85 |
| p95 geral | 21497.2 ms | 12529.4 ms |
| p95 pedidos-do-cliente | 25979.5 ms | 11336.1 ms |
| CPU banco / API | 98.2% / 7.5% | 98.2% / 12.7% |
| Memória banco / API | 391.1 MiB / 29.9 MiB | 392.2 MiB / 42.6 MiB |
| Erros | 0.00% nas 3 | 0.00%, 0.00% e 0.30% |

Pastas do depois:
[`20261111-204310`](resultados/20261111-204310-02-indice-itens-pedido/resumo.txt) ·
[`20261111-204442`](resultados/20261111-204442-02-indice-itens-pedido/resumo.txt) ·
[`20261111-204617`](resultados/20261111-204617-02-indice-itens-pedido/resumo.txt)

**Conclusão: aplicada e medida, com ganho.** A parte da hipótese sobre a rota se confirmou: o p95 de `pedidos-do-cliente` caiu de 25979.5 ms para 11336.1 ms, e a aplicação inteira passou de 2.93 para 4.85 req/s, uma diferença maior que a variação entre execuções (as 3 medições da 02 ficaram entre 4.47 e 5.07 req/s; as da 01, entre 2.91 e 2.95). A parte sobre a CPU do banco **não** se confirmou: ela continuou em ~98%. A leitura mais provável é que o banco segue saturado, mas agora gasta a CPU atendendo mais requisições; as rotas que ainda leem tabelas inteiras (`top-produtos`, `vendas-por-dia`, `pedidos-por-status`) continuam disputando a mesma CPU.

**Erro na 3ª execução:** 1 requisição de `top-produtos` passou do limite de 60 s do teste de carga (`request timeout`), o que deu 0.30% de erros naquela execução. A rota já levava de 15 a 30 s na linha de base; é o próximo sintoma a investigar.

### 03 · Índice em `pedidos (status, criado_em DESC, id DESC)`

- **Diagnóstico que motivou:** depois da 02, rodei o `EXPLAIN ANALYZE` de cada consulta das rotas com o banco sem carga ([`diagnostico/03-consultas-por-rota.txt`](diagnostico/03-consultas-por-rota.txt)). A rota `pedidos-por-status` (15% da carga) faz duas consultas que leem a tabela `pedidos` inteira: o `count(*)` (`Parallel Seq Scan on pedidos`, `Execution Time: 79.658 ms`) e a página com `ORDER BY criado_em DESC, id DESC LIMIT 20 OFFSET 9980` (`Parallel Seq Scan on pedidos` seguido de ordenação, `Execution Time: 322.556 ms`). Considerando o peso de cada rota na carga, é a que mais consome o banco; `top-produtos` é a consulta mais lenta (`1230.605 ms`), mas tem só 2% da carga.
- **Hipótese** (registrada antes da mudança): criar um índice em `pedidos (status, criado_em DESC, id DESC)` deve reduzir o p95 da rota `pedidos-por-status` e aumentar as requisições por segundo, porque a página passa a ser lida já ordenada pelo índice, sem ler e ordenar todos os pedidos do status, e o `count(*)` pode contar pelo índice em vez de ler a tabela.
- **O que refutaria a hipótese:** o p95 de `pedidos-por-status` e as req/s ficarem dentro da variação da 02.
- **Limite já esperado:** o `OFFSET` continua obrigando o banco a percorrer as linhas das páginas anteriores (até 19.980 na página 1000), e o `count(*)` continua contando todas as linhas do status (até 300 mil para `pago`); o índice deixa as duas coisas mais baratas, mas não elimina esse trabalho.
- **Antes:** mudança 02.
- **Mudança:** [`banco/05-indice-pedidos-status.sql`](banco/05-indice-pedidos-status.sql), commit `945543e`.

**Diagnóstico das consultas** (`EXPLAIN ANALYZE` com o banco sem carga, status `pago`):

| Consulta | Antes ([`03-consultas-por-rota.txt`](diagnostico/03-consultas-por-rota.txt)) | Depois ([`03-pedidos-por-status-depois.txt`](diagnostico/03-pedidos-por-status-depois.txt)) |
|---|---|---|
| `count(*)` | `Parallel Seq Scan`, 79.658 ms | `Parallel Index Only Scan`, 75.258 ms |
| Página com `OFFSET 9980` | `Parallel Seq Scan` + ordenação, 322.556 ms | `Index Scan`, 8.664 ms |

O mesmo arquivo mostra mais dois casos: `OFFSET 19980` de `pago` com `Index Scan` em 10.189 ms, e `OFFSET 19980` de `pendente`, em que o banco escolheu outro plano (`Parallel Bitmap Heap Scan` + ordenação) e levou 174.951 ms.

**Carga:**

| Métrica | Antes (02) | Depois (03) |
|---|---|---|
| Req/s | 4.85 | 5.27 |
| p95 geral | 12529.4 ms | 11714.9 ms |
| Mediana pedidos-por-status | 5498.3 ms | 2912.8 ms |
| p95 pedidos-por-status | 9502.9 ms | 16451.8 ms |
| CPU banco / API | 98.2% / 12.7% | 99.5% / 16.9% |
| Memória banco / API | 392.2 MiB / 42.6 MiB | 417.2 MiB / 41.7 MiB |
| Erros | 0.00%, 0.00% e 0.30% | 0.00% nas 3 |

Pastas do depois:
[`20261111-205156`](resultados/20261111-205156-03-indice-pedidos-status/resumo.txt) ·
[`20261111-205330`](resultados/20261111-205330-03-indice-pedidos-status/resumo.txt) ·
[`20261111-205505`](resultados/20261111-205505-03-indice-pedidos-status/resumo.txt)

**Conclusão: aplicada, sem ganho claro.** A hipótese se confirmou só em parte. A página ficou muito mais barata (322.556 ms para 8.664 ms) e a mediana da rota caiu (5498.3 ms para 2912.8 ms), mas o p95 da rota subiu (9502.9 ms para 16451.8 ms) e o ganho geral (4.85 para 5.27 req/s) está dentro da variação: as 3 execuções da 03 ficaram entre 4.99 e 6.62 req/s, e as da 02 entre 4.47 e 5.07. A explicação que o diagnóstico sustenta: o `count(*)` praticamente não mudou (79.658 ms para 75.258 ms), porque, mesmo lendo só o índice, o banco ainda precisa contar cada um dos até 300 mil pedidos do status, em toda requisição. Com o banco ainda a ~100% de CPU, a rota continua esperando na fila atrás de `top-produtos` e `vendas-por-dia`. O p95 da rota tem poucas amostras (44 a 57 requisições por execução), então não trato a subida como piora confirmada.

**Próximo passo sugerido pelo diagnóstico:** o total por status é sempre o mesmo para um mesmo banco (a API só lê, não grava), então ele não precisaria ser recontado a cada requisição.

### 04 · Ranking de `top-produtos` pré-calculado numa visão materializada

- **Diagnóstico que motivou:** em [`diagnostico/03-consultas-por-rota.txt`](diagnostico/03-consultas-por-rota.txt), a consulta de `top-produtos` lê as tabelas `itens_pedido` (~1,5 milhão de linhas), `pedidos` e `produtos` inteiras, com `Parallel Seq Scan` em 3 processos, e leva `1230.605 ms` com o banco sem carga. É a consulta mais cara da aplicação. Mesmo com só 2% da carga, cada chamada ocupa o banco por mais tempo que todas as outras rotas; na 02 uma chamada passou do limite de 60 s do teste de carga.
- **Por que não um índice:** a consulta soma todos os itens de pedidos não cancelados. Ela precisa ler praticamente todas as linhas de qualquer jeito, então um índice não evita esse trabalho.
- **Mudança:** calcular o ranking uma vez, quando o banco é criado, numa visão materializada (`banco/06-top-produtos.sql`), e fazer a rota ler o resultado pronto, mantendo o mesmo `ORDER BY receita_centavos DESC, id` e o mesmo `LIMIT`.
- **Hipótese** (registrada antes da mudança): pré-calcular o ranking deve reduzir o p95 de `top-produtos` de dezenas de segundos para perto do tempo de uma consulta simples, e aumentar as req/s da aplicação, porque libera a CPU do banco que hoje é gasta somando 1,5 milhão de itens a cada chamada.
- **O que refutaria a hipótese:** as req/s ficarem dentro da variação da 03. Nesse caso, o custo de `top-produtos` era pequeno perto do resto, por causa do peso de só 2%.
- **Custo e limite:** a visão ocupa espaço no banco (uma linha por produto vendido) e fica parada no tempo: se a loja recebesse pedidos novos, o ranking precisaria ser recalculado (`REFRESH MATERIALIZED VIEW`). Nesta aplicação a API só lê, então os valores são sempre os mesmos.
- **Antes:** mudança 03.
- **Commit da mudança:** `d876bf6` ([`banco/06-top-produtos.sql`](banco/06-top-produtos.sql) e a rota em [`api/src/rotas.js`](api/src/rotas.js)). Antes de medir, o contrato foi conferido: `Contrato mantido`.

**Diagnóstico da consulta** (`EXPLAIN ANALYZE` com o banco sem carga, `LIMIT 10`):

| | Antes ([`03-consultas-por-rota.txt`](diagnostico/03-consultas-por-rota.txt)) | Depois ([`04-top-produtos-depois.txt`](diagnostico/04-top-produtos-depois.txt)) |
|---|---|---|
| Plano | `Parallel Seq Scan` em `itens_pedido`, `pedidos` e `produtos`, agregação e ordenação | `Index Scan using idx_top_produtos_receita on top_produtos` |
| Execution Time | 1230.605 ms | 16.328 ms |

**Carga:**

| Métrica | Antes (03) | Depois (04) |
|---|---|---|
| Req/s | 5.27 | 7.85 |
| p95 geral | 11714.9 ms | 9635.0 ms |
| p95 top-produtos | 29313.8 ms | 532.1 ms |
| p95 pedidos-por-status | 16451.8 ms | 4621.1 ms |
| p95 vendas-por-dia | 14771.7 ms | 5217.6 ms |
| CPU banco / API | 99.5% / 16.9% | 98.8% / 20.5% |
| Memória banco / API | 417.2 MiB / 41.7 MiB | 456.3 MiB / 36.6 MiB |
| Erros | 0.00% nas 3 | 0.00% nas 3 |

Pastas do depois:
[`20261111-210204`](resultados/20261111-210204-04-top-produtos-materializado/resumo.txt) ·
[`20261111-210331`](resultados/20261111-210331-04-top-produtos-materializado/resumo.txt) ·
[`20261111-210457`](resultados/20261111-210457-04-top-produtos-materializado/resumo.txt)

**Conclusão: aplicada e medida, com ganho.** A hipótese se confirmou. O p95 de `top-produtos` caiu de 29313.8 ms para 532.1 ms e a aplicação passou de 5.27 para 7.85 req/s; as 3 execuções da 04 ficaram entre 7.53 e 8.44 req/s, todas acima da maior da 03 (6.62). O efeito apareceu também em rotas que não foram alteradas, como `pedidos-por-status` e `vendas-por-dia`: elas disputavam a CPU do banco com as somas de `top-produtos`, que ocupavam 3 processos por mais de 1 s a cada chamada. O banco continua a ~99% de CPU, agora atendendo mais requisições. A memória média do banco subiu de 417.2 MiB para 456.3 MiB, ainda abaixo do limite de 512 MB; não verifiquei se a causa é a visão materializada.

### 05 · Pool de conexões na API

- **Diagnóstico que motivou:** em [`api/src/db.js`](api/src/db.js), a função `consultar` abre uma conexão nova com o banco a cada consulta e fecha no fim. A rota `pedidos-do-cliente` (20% da carga e a mais lenta depois da 04) faz uma consulta por pedido e uma por item, então abre dezenas de conexões por requisição. Medi o custo dentro do container da API, sem carga ([`diagnostico/05-custo-de-conexao.txt`](diagnostico/05-custo-de-conexao.txt)): 300 consultas `SELECT 1` levaram em média 6.073 ms cada abrindo uma conexão nova, e 0.112 ms cada reaproveitando uma única conexão.
- **Mudança:** trocar o `new Client()` por consulta por um `Pool` do `pg`, que mantém até 10 conexões abertas e as reaproveita. Nenhuma consulta SQL muda.
- **Hipótese** (registrada antes da mudança): usar um pool de conexões deve reduzir o p95 de `pedidos-do-cliente` e aumentar as req/s da aplicação, porque cada consulta deixa de pagar a abertura de uma conexão, e o banco deixa de gastar CPU criando um processo novo para cada conexão.
- **O que refutaria a hipótese:** as req/s e o p95 de `pedidos-do-cliente` ficarem dentro da variação da 04. Nesse caso, o custo de conexão seria pequeno perto do tempo das consultas sob carga.
- **Risco:** com no máximo 10 conexões, quando todas estiverem ocupadas as consultas esperam na fila do pool, dentro da API. Como o banco tem 1 CPU, mais conexões simultâneas não deveriam fazê-lo trabalhar mais rápido.
- **Antes:** mudança 04.
- **Commit da mudança:** `38acfeb` ([`api/src/db.js`](api/src/db.js)). Antes de medir, o contrato foi conferido: `Contrato mantido`.

**Carga:**

| Métrica | Antes (04) | Depois (05) |
|---|---|---|
| Req/s | 7.85 | 21.50 |
| p95 geral | 9635.0 ms | 3282.7 ms |
| p95 pedidos-do-cliente | 12392.4 ms | 4492.0 ms |
| CPU banco / API | 98.8% / 20.5% | 96.6% / 29.6% |
| Memória banco / API | 456.3 MiB / 36.6 MiB | 474.2 MiB / 35.5 MiB |
| Erros | 0.00% nas 3 | 0.00% nas 3 |

Pastas do depois:
[`20261111-211050`](resultados/20261111-211050-05-pool-de-conexoes/resumo.txt) ·
[`20261111-211212`](resultados/20261111-211212-05-pool-de-conexoes/resumo.txt) ·
[`20261111-211335`](resultados/20261111-211335-05-pool-de-conexoes/resumo.txt)

**Conclusão: aplicada e medida, com ganho.** A hipótese se confirmou: a aplicação passou de 7.85 para 21.50 req/s (as 3 execuções ficaram entre 20.11 e 21.74, muito acima da faixa da 04, de 7.53 a 8.44), e o p95 de `pedidos-do-cliente` caiu de 12392.4 ms para 4492.0 ms. Abrir uma conexão por consulta era o maior desperdício da aplicação. O banco continua perto do limite de CPU (96.6%) e a API passou a usar mais CPU (29.6% de 1 CPU, com limite de 0,5 CPU), porque agora atende muito mais requisições.

**Ponto de atenção:** a memória do banco subiu para 474.2 MiB de média, com pico de 493.0 MiB numa das execuções ([`recursos.txt`](resultados/20261111-211050-05-pool-de-conexoes/recursos.txt)), perto do limite de 512 MB. Uma causa provável, que não verifiquei, são os processos das 10 conexões que agora ficam abertas o tempo todo.

### 06 · Tirar o N+1 de `pedidos-do-cliente`

- **Diagnóstico que motivou:** depois da 05, `pedidos-do-cliente` continua a rota mais lenta (p95 de 4492.0 ms, 20% da carga). O código faz 1 consulta do cliente, 1 dos pedidos, 1 de itens para cada pedido e 1 de produto para cada item. Contando no banco ([`diagnostico/06-consultas-por-requisicao.txt`](diagnostico/06-consultas-por-requisicao.txt)), todo cliente tem 5 pedidos e, em média, 15 itens, o que dá em média 22 consultas por requisição (no máximo 32).
- **Mudança:** buscar os itens de todos os pedidos do cliente numa consulta só, com `JOIN` em `produtos` para trazer o nome, e agrupar por pedido em JavaScript, mantendo a ordem por id do item. A rota passa a fazer sempre 3 consultas.
- **Hipótese** (registrada antes da mudança): trocar as ~22 consultas por requisição por 3 deve reduzir o p95 de `pedidos-do-cliente` e aumentar as req/s, porque cada consulta tem um custo fixo de ida e volta ao banco e de planejamento, que hoje se repete dezenas de vezes por requisição.
- **O que refutaria a hipótese:** as req/s e o p95 de `pedidos-do-cliente` ficarem dentro da variação da 05. Nesse caso, depois do pool, o custo por consulta já seria pequeno demais para importar.
- **Antes:** mudança 05.
- **Commit da mudança:** `7520686` ([`api/src/rotas.js`](api/src/rotas.js)). Antes de medir, o contrato foi conferido: `Contrato mantido`.

**Carga:**

| Métrica | Antes (05) | Depois (06) |
|---|---|---|
| Req/s | 21.50 | 20.88 |
| p95 geral | 3282.7 ms | 2216.3 ms |
| Mediana geral | 585.5 ms | 791.3 ms |
| p95 pedidos-do-cliente | 4492.0 ms | 1730.6 ms |
| Mediana cliente | 115.9 ms | 320.0 ms |
| p95 pedidos-por-status | 1903.5 ms | 2720.0 ms |
| p95 vendas-por-dia | 2336.5 ms | 3969.3 ms |
| CPU banco / API | 96.6% / 29.6% | 98.0% / 27.2% |
| Memória banco / API | 474.2 MiB / 35.5 MiB | 470.5 MiB / 45.6 MiB |
| Erros | 0.00% nas 3 | 0.00% nas 3 |

Pastas do depois:
[`20261111-211914`](resultados/20261111-211914-06-sem-n-mais-1/resumo.txt) ·
[`20261111-212038`](resultados/20261111-212038-06-sem-n-mais-1/resumo.txt) ·
[`20261111-212206`](resultados/20261111-212206-06-sem-n-mais-1/resumo.txt)

**Conclusão: aplicada, ganho parcial.** A parte da hipótese sobre a rota se confirmou: o p95 de `pedidos-do-cliente` caiu de 4492.0 ms para 1730.6 ms, e com isso o p95 geral caiu de 3282.7 ms para 2216.3 ms. A parte sobre as req/s **não** se confirmou: 20.88 está dentro da faixa da 05 (20.11 a 21.74). As outras rotas ficaram mais lentas (por exemplo, a mediana de `cliente` subiu de 115.9 ms para 320.0 ms).

Minha leitura, que ainda não verifiquei com diagnóstico próprio: com o pool, o custo das ~22 consultas era sobretudo espera (ida e volta até o banco), e não trabalho de CPU do banco. Tirar o N+1 reduziu a espera daquela rota, mas o banco continuou fazendo praticamente o mesmo trabalho total e seguiu a ~98% de CPU. Como os 20 usuários virtuais pedem sem pausa, o tempo que `pedidos-do-cliente` deixou de esperar virou mais requisições das outras rotas disputando a mesma CPU, e elas passaram a esperar mais. O total de requisições por segundo continua limitado pela CPU do banco.

**Ponto de atenção:** a memória do banco teve pico de 500.1 MiB numa das execuções ([`recursos.txt`](resultados/20261111-212038-06-sem-n-mais-1/recursos.txt)), perto do limite de 512 MB.

### 07 · Total de pedidos por status pré-calculado

- **Diagnóstico que motivou:** na 03, o índice deixou a página de `pedidos-por-status` barata, mas o `count(*)` quase não mudou: 75.258 ms com o banco sem carga ([`diagnostico/03-pedidos-por-status-depois.txt`](diagnostico/03-pedidos-por-status-depois.txt)), porque o banco conta, a cada chamada, todos os pedidos do status (até 300 mil para `pago`). A rota tem 15% da carga. Pelos tempos de [`diagnostico/03-consultas-por-rota.txt`](diagnostico/03-consultas-por-rota.txt) ponderados pelo peso de cada rota, é a maior conta de CPU que sobrou no banco. A 06 mostrou que só ganha req/s a mudança que reduz o trabalho do banco.
- **Mudança:** contar os pedidos de cada status uma vez, quando o banco é criado, numa visão materializada (`banco/07-contagem-por-status.sql`), e fazer a rota ler o total pronto. Como na 04, a mudança tem um `.sql` novo e a alteração na rota, que não funcionam separados.
- **Hipótese** (registrada antes da mudança): pré-calcular o total por status deve aumentar as req/s da aplicação e reduzir o p95 de `pedidos-por-status`, porque tira do banco a contagem de até 300 mil linhas em 15% das requisições.
- **O que refutaria a hipótese:** as req/s ficarem dentro da variação da 06 (20.85 a 22.06).
- **Custo e limite:** os mesmos da 04. A visão fica parada no tempo e precisaria de `REFRESH MATERIALIZED VIEW` se a loja recebesse pedidos novos; nesta aplicação a API só lê.
- **Antes:** mudança 06.
- **Commit da mudança:** `51fb185` ([`banco/07-contagem-por-status.sql`](banco/07-contagem-por-status.sql) e a rota em [`api/src/rotas.js`](api/src/rotas.js)). Antes de medir, o contrato foi conferido: `Contrato mantido`.

**Diagnóstico da consulta** (`EXPLAIN ANALYZE` com o banco sem carga, status `pago`, [`diagnostico/07-contagem-por-status-depois.txt`](diagnostico/07-contagem-por-status-depois.txt)): ler o total pronto levou 0.222 ms. No mesmo arquivo, o `count(*)` antigo, rodado de novo para comparar, levou 30.784 ms; na 03 a mesma consulta tinha levado 75.258 ms. O tempo de uma consulta isolada também varia bastante entre execuções.

**Carga:**

| Métrica | Antes (06) | Depois (07) |
|---|---|---|
| Req/s | 20.88 | 20.70 |
| p95 geral | 2216.3 ms | 2404.6 ms |
| Mediana pedidos-por-status | 1119.5 ms | 901.6 ms |
| p95 pedidos-por-status | 2720.0 ms | 2988.9 ms |
| CPU banco / API | 98.0% / 27.2% | 96.1% / 30.4% |
| Memória banco / API | 470.5 MiB / 45.6 MiB | 468.8 MiB / 39.7 MiB |
| Erros | 0.00% nas 3 | 0.00% nas 3 |

Pastas do depois:
[`20261111-213017`](resultados/20261111-213017-07-contagem-por-status/resumo.txt) ·
[`20261111-213141`](resultados/20261111-213141-07-contagem-por-status/resumo.txt) ·
[`20261111-213305`](resultados/20261111-213305-07-contagem-por-status/resumo.txt)

**Conclusão: aplicada, sem ganho. Hipótese refutada.** As req/s (20.33 a 21.10) ficaram dentro da faixa da 06 (20.85 a 22.06), e o p95 geral não caiu. A mediana de `pedidos-por-status` caiu um pouco, mas o p95 da rota não.

**O que isso ensina sobre o meu método:** escolhi a 07 multiplicando o tempo de cada consulta, medido com o banco parado, pelo peso da rota na carga. Esse método acertou na 04, mas errou aqui. Duas fraquezas aparecem nos próprios dados: o tempo de uma consulta isolada varia muito (75.258 ms na 03 e 30.784 ms agora, para a mesma consulta), e uma consulta rodada sozinha não mostra quanto ela custa quando disputa a CPU com as outras. Antes de outra mudança no banco, o próximo passo deveria ser medir **sob carga** quanto tempo de banco cada consulta ocupa (por exemplo, com a extensão `pg_stat_statements` do PostgreSQL), em vez de estimar.
