# Próximos testes

Ideias que apareceram na pesquisa ou no diagnóstico e **não foram testadas**. Nenhuma tem resultado medido; o "ganho esperado" é uma expectativa, não um número.

Contexto comum a todas: depois da mudança 07, o banco continua perto de 100% da CPU disponível (entre 94.9% e 97.7% de média nas execuções da 07) e a memória média do banco fica perto do limite de 512 MB (468.8 MiB de média; pico de 501.1 MiB em [`20261111-213141`](resultados/20261111-213141-07-contagem-por-status/recursos.txt)). A API usa cerca de 30% de 1 CPU, com limite de 0,5 CPU.

---

## 1. Medir sob carga o tempo de banco de cada consulta (`pg_stat_statements`)

- **De onde veio:** a mudança 07 refutou uma hipótese escolhida a partir de `EXPLAIN ANALYZE` com o banco parado (seção 07 do [`experimentos.md`](experimentos.md)). A extensão `pg_stat_statements` registra estatísticas de planejamento e execução de todas as consultas executadas pelo servidor ([PostgreSQL 16: pg_stat_statements](https://www.postgresql.org/docs/16/pgstatstatements.html)).
- **O que acredito que ganharia:** não é uma otimização, é um diagnóstico. Mostraria qual consulta ocupa mais tempo do banco durante a carga real, para escolher a próxima mudança com evidência em vez de estimativa.
- **Como testaria:** adicionar `-c shared_preload_libraries=pg_stat_statements` ao `command` do serviço `banco` e um `banco/08-...sql` com `CREATE EXTENSION pg_stat_statements;`; recriar o banco, rodar o `medir.sh` e salvar em `diagnostico/` o resultado de `SELECT query, calls, total_exec_time FROM pg_stat_statements ORDER BY total_exec_time DESC`.
- **O que precisaria:** medir também o custo da própria extensão (ela usa memória compartilhada extra, segundo a documentação), já que a memória do banco está perto do limite.

## 2. Desligar as consultas paralelas no PostgreSQL

- **De onde veio:** vários planos em [`diagnostico/`](diagnostico/) mostram `Workers Launched: 2`, ou seja, 3 processos por consulta. A documentação diz que o processo principal pede processos de apoio ao chegar no nó `Gather`, limitados por `max_parallel_workers_per_gather` ([PostgreSQL 16: How Parallel Query Works](https://www.postgresql.org/docs/16/how-parallel-query-works.html)).
- **O que acredito que ganharia:** o banco tem limite de 1 CPU; dividir uma consulta em 3 processos não deveria deixá-la mais rápida sob carga, e cada processo extra ocupa memória. Espero CPU igual ou um pouco menor e memória menor.
- **Como testaria:** `-c max_parallel_workers_per_gather=0` no `command` do serviço `banco`, `docker compose up -d`, contrato, 3 medições contra a 07.
- **O que precisaria:** nada além do ciclo normal. É a mudança mais barata da lista.

## 3. Índice de expressão para `cliente-por-email`

- **De onde veio:** [`diagnostico/03-consultas-por-rota.txt`](diagnostico/03-consultas-por-rota.txt) mostra `Seq Scan on clientes` para `lower(email) = lower(...)` (22.019 ms com o banco parado). A documentação usa justamente `lower(col1)` como exemplo de índice sobre expressão ([PostgreSQL 16: Indexes on Expressions](https://www.postgresql.org/docs/16/indexes-expressional.html)).
- **O que acredito que ganharia:** a rota tem 15% da carga; deixaria de ler os 100 mil clientes por chamada.
- **Como testaria:** `banco/08-indice-email.sql` com `CREATE INDEX ... ON clientes (lower(email));`, recriar o banco, contrato, 3 medições.
- **O que precisaria:** a mesma documentação avisa que índices de expressão custam mais para manter a cada escrita; nesta API só há leitura.

## 4. `vendas-por-dia` sem converter a data na consulta

- **De onde veio:** a consulta filtra `p.criado_em::date BETWEEN $1 AND $2`, e o plano em [`diagnostico/03-consultas-por-rota.txt`](diagnostico/03-consultas-por-rota.txt) mostra `Parallel Seq Scan on pedidos p` (106.809 ms com o banco parado). Pela mesma página de [Indexes on Expressions](https://www.postgresql.org/docs/16/indexes-expressional.html), um índice só é usado quando a consulta usa a mesma expressão do índice.
- **O que acredito que ganharia:** reescrevendo o filtro como intervalo (`criado_em >= inicio AND criado_em < fim + 1 dia`) e criando um índice em `pedidos (criado_em)`, a consulta leria só os pedidos do período.
- **Como testaria:** mudança na rota + `banco/08-...sql`, contrato (atenção especial aos casos de borda de data do contrato), 3 medições.
- **O que precisaria:** confirmar que as duas formas do filtro dão exatamente o mesmo resultado para `timestamp` sem fuso; o contrato tem 7 casos dessa rota.

## 5. Buscar só as colunas usadas

- **De onde veio:** `SELECT *` em `pedidos` traz a coluna `observacoes`, um texto longo que nenhuma resposta usa (exceto que `vendas-por-dia` também a seleciona e descarta). Yang et al. classificam isso como "Unnecessary Data Retrieval", um dos 9 anti-padrões encontrados em aplicações reais ([Yang et al., ICSE 2018](https://par.nsf.gov/servlets/purl/10067547)).
- **O que acredito que ganharia:** menos dados lidos e transferidos por consulta; ganho provavelmente pequeno, porque o banco ainda lê a linha inteira da tabela.
- **Como testaria:** trocar `SELECT *` pelas colunas usadas em cada rota, contrato, 3 medições.

## 6. Concorrência: consultas em paralelo, pool maior ou vários processos Node

- **De onde veio:** pergunta feita durante o trabalho. A documentação do `node-postgres` lembra que o servidor só atende um número limitado de clientes ao mesmo tempo ([node-postgres: Pooling](https://node-postgres.com/features/pooling)); Freund mostra que o PostgreSQL não escala bem com muitas conexões abertas, mesmo ociosas ([Freund, 2020](https://www.citusdata.com/blog/2020/10/08/analyzing-connection-scalability/)).
- **Por que não testei:** o recurso no limite é a CPU do banco. Disparar mais consultas ao mesmo tempo (`Promise.all`, pool maior que 10) não reduz o trabalho do banco, e cada conexão a mais ocupa memória, que já está perto do limite. Rodar mais processos Node (cluster) usaria mais CPU na API, que não é o gargalo e tem limite de 0,5 CPU. A mudança 06 é evidência indireta: reduzir a espera de uma rota não aumentou as req/s.
- **O que mudaria esta conclusão:** se, depois de outras mudanças, a CPU do banco cair e a da API encostar no limite, aí concorrência na API passa a fazer sentido.
- **Como testaria:** variar `max` do pool (5, 10, 20) em mudanças separadas, comparando req/s e memória do banco.

## 7. Cache na frente do banco (Redis, padrão cache-aside)

- **De onde veio:** a documentação do Redis descreve o padrão cache-aside: a aplicação lê do cache, busca no banco quando não encontra e guarda o resultado, com um tempo de expiração que limita quanto tempo um dado velho pode ser servido ([Redis: cache-aside](https://redis.io/docs/latest/develop/use-cases/cache-aside/)).
- **O que acredito que ganharia:** rotas muito repetidas (como `cliente`) deixariam de chegar ao banco.
- **Por que não testei:** é um serviço novo, ou seja, custo a mais (CPU e memória de outro container), e o enunciado pede que esse custo apareça junto do ganho. Também traz risco de dado velho. Antes, preferi reduzir o trabalho do próprio banco.
- **Como testaria:** serviço `redis` no `docker-compose.yml` com limite de recursos, cache-aside numa rota por vez, 3 medições, somando o consumo do novo container no custo.

## 8. Log da API sem o corpo da resposta

- **De onde veio:** leitura do código. O middleware em [`api/src/server.js`](api/src/server.js) faz `JSON.stringify` da resposta inteira de cada requisição e escreve no console.
- **O que acredito que ganharia:** menos CPU na API. Como a API não é o gargalo hoje, espero pouco efeito nas req/s; o efeito apareceria se a API virasse o limite.
- **Como testaria:** registrar só método, URL, status e duração; 3 medições comparando a CPU da API.
- **O que precisaria:** confirmar com quem usa os logs que o corpo da resposta não é necessário.

## 9. Paginação por "keyset" em vez de `OFFSET`

- **De onde veio:** Winand explica que, com `OFFSET`, o banco ainda precisa buscar e ordenar as linhas das páginas anteriores antes de devolver as seguintes, e propõe filtrar só o que ainda não foi visto ([Winand: no-offset](https://use-the-index-luke.com/no-offset)). O diagnóstico da 03 mostra o índice percorrendo 20000 linhas para devolver 20 na página 1000.
- **Por que não testei:** mudaria o contrato da rota `/pedidos`, que recebe `pagina=` e precisa continuar recebendo. Só faria sentido numa nova versão da API.

## 10. Reduzir os limites de recursos (custo)

- **De onde veio:** o enunciado pede uma aplicação "mais rápida e mais barata". A API usa cerca de 30% de 1 CPU com limite de 0,5 CPU (por exemplo, 30.4% em [`20261111-213017`](resultados/20261111-213017-07-contagem-por-status/recursos.txt)).
- **O que acredito que ganharia:** testar um limite menor para a API e ver se as req/s se mantêm. O banco não pode ser reduzido enquanto estiver no limite de CPU e perto do limite de memória.
- **Como testaria:** mudar `cpus` da API no `docker-compose.yml`, 3 medições.
