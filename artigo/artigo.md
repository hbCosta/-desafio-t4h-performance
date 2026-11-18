# De 2.69 para 20.70 requisições por segundo sem mais hardware: o gargalo era o banco, e a maior perda era abrir conexões

## 1. Resumo

A API de uma loja fictícia (Node.js e PostgreSQL, em containers com limite de CPU e memória) ficava lenta sob carga porque o banco trabalhava o tempo todo no limite de 1 CPU. Testei sete mudanças, uma por vez, medindo cada uma três vezes. Quatro deram ganho claro ou parcial, três não. Com os mesmos limites de recursos, a aplicação passou de 2.69 para 20.70 requisições por segundo, e o p95 caiu de 26751.0 ms para 2404.6 ms. O maior ganho isolado veio de reaproveitar conexões com o banco. O banco continua no limite de CPU.

## 2. Contexto e diagnóstico

A carga simula 20 usuários fazendo pedidos sem pausa por 60 segundos, em sete rotas com pesos fixos. Na linha de base, o banco ficou entre 96.8% e 99.8% de CPU, e a API entre 9.1% e 10.7% ([medição](../resultados/20261111-192841-00-linha-de-base/recursos.txt)). Ou seja, a API passava a maior parte do tempo esperando o banco.

Para saber o que o banco fazia, rodei `EXPLAIN ANALYZE` nas consultas de cada rota e salvei a saída em [`diagnostico/`](../diagnostico/). Encontrei quatro problemas:

- **Leitura de tabelas inteiras.** Buscar os pedidos de um cliente lia os 500 mil pedidos (`Parallel Seq Scan`, 202.952 ms), e buscar os itens de um pedido lia os ~1,5 milhão de itens (116.237 ms) ([pedidos](../diagnostico/00-pedidos-por-cliente.txt), [itens](../diagnostico/00-itens-por-pedido.txt)).
- **Uma conexão nova por consulta.** No [código](../api/src/db.js) original, cada consulta abria e fechava uma conexão. Medi 6.073 ms por consulta assim, contra 0.112 ms reaproveitando a conexão ([diagnóstico](../diagnostico/05-custo-de-conexao.txt)).
- **N+1.** A rota de pedidos do cliente fazia uma consulta por pedido e outra por item: em média 22 consultas por requisição ([contagem](../diagnostico/06-consultas-por-requisicao.txt)).
- **Agregações refeitas a cada chamada.** O ranking de produtos somava todos os itens a cada chamada (1230.605 ms), e a paginação recontava até 300 mil pedidos ([diagnóstico](../diagnostico/03-consultas-por-rota.txt)).

Hipóteses de causa: (1) sem índices, o banco lê tabelas inteiras para achar poucas linhas; (2) abrir conexões custa mais que as consultas; (3) o N+1 multiplica idas e voltas ao banco; (4) resultados que não mudam são recalculados em toda requisição.

## 3. Estado da arte

### Índices e planos de consulta

A documentação do PostgreSQL explica que um índice B-tree na mesma ordem do `ORDER BY` evita a etapa de ordenação, e que com `LIMIT` as primeiras linhas saem "sem varrer o restante" [1]. O `EXPLAIN ANALYZE` executa a consulta e mostra linhas e tempos reais, incluindo as linhas descartadas pelo filtro [2]. Um índice sobre uma expressão, como `lower(email)`, só é usado quando a consulta usa a mesma expressão [3]. No estudo de Yang et al. com 12 aplicações web reais, falta de índice foi a causa mais comum entre os problemas de desempenho registrados nos sistemas de bugs [4].

### Custo de conexões

O PostgreSQL usa um modelo de "um processo por usuário": cada conexão nova cria um processo no servidor [5]. A documentação do `node-postgres` diz que conectar um cliente exige um handshake de 20 a 30 ms e recomenda um pool [6]. Freund, committer do PostgreSQL, cita o custo de estabelecer conexões como o motivo de as aplicações manterem pools, e mostra que muitas conexões abertas prejudicam o desempenho, mesmo ociosas [7]. No mercado, o Heroku oferece pool no servidor (PgBouncer) justamente para reduzir a frequência com que o banco cria processos [8].

### N+1 e consultas em laço

Chen et al. chamam de "one-by-one processing" o padrão de repetir operações parecidas no banco dentro de um laço. Eles também observam que, quando o tempo de resposta já é pequeno, agrupar as consultas melhora pouco [9]. Yang et al. encontraram o N+1 em 15 ações problemáticas; num dos exemplos, juntar 51 consultas em uma reduziu o carregamento de 1.10 s para 0.34 s [4].

### Pré-calcular e guardar resultados

Uma visão materializada guarda o resultado de uma consulta em forma de tabela. Segundo a documentação, o acesso costuma ser muito mais rápido, mas os dados "nem sempre estão atualizados" e precisam de `REFRESH MATERIALIZED VIEW` [10]. Yang et al. descrevem o mesmo dilema ao decidir se um campo derivado deve ser guardado no banco [4]. Fora do banco, o padrão cache-aside com Redis limita por tempo de expiração quanto um dado pode estar velho [11].

## 4. Alternativas consideradas

As avaliações abaixo são minha opinião, apoiada nas fontes e nas medições.

| Alternativa | Custo | Desempenho esperado | Risco | Esforço |
|---|---|---|---|---|
| Índices nas colunas filtradas | Espaço em disco | Alto onde há leitura completa | Baixo; só leitura nesta API | Baixo (um `.sql`) |
| Pool de conexões | Nenhum recurso novo | Alto: tira um custo fixo de cada consulta | Baixo; precisa limitar o tamanho | Baixo (um arquivo) |
| Eliminar o N+1 | Nenhum | Médio: menos espera por requisição | Médio: reescrever a montagem da resposta | Médio |
| Visões materializadas | Espaço; dado parado no tempo | Alto para agregações caras | Médio: precisa de `REFRESH` com escrita | Baixo |
| Cache externo (Redis) | Um serviço a mais (CPU e memória) | Alto para leituras repetidas | Dado velho; invalidação | Alto |
| Mais CPU para o banco | Custo direto de infraestrutura | Provavelmente alto | Baixo | Muito baixo |
| Concorrência na API | Nenhum | Baixo enquanto o banco for o limite | Mais conexões e memória no banco | Médio |

As quatro primeiras atacam diretamente os quatro problemas do diagnóstico e não pedem recurso novo, então o custo de errar é baixo: se não funcionar, basta desfazer um commit. As duas seguintes resolvem o sintoma por fora. Mais CPU é a saída mais fácil, mas aumenta o custo, o oposto do que o desafio pede. O Redis tiraria leituras repetidas do banco, mas soma um container ao custo e cria o problema de invalidar o cache, que as fontes apontam como a parte difícil [11]. A concorrência na API foi uma dúvida que surgiu durante o trabalho; a coloquei na tabela porque o motivo para descartá-la ajuda a entender o gargalo. Com o banco no limite, mandar mais consultas ao mesmo tempo só aumenta a fila e o número de conexões, que as fontes mostram ter custo próprio [7].

## 5. Solução escolhida e por quê

Escolhi o que reduz o trabalho do banco **sem aumentar recursos**: índices, pool de conexões, eliminação do N+1 e visões materializadas para as agregações. Meu argumento: com o banco no limite de CPU, só ganha capacidade a mudança que faz o banco trabalhar menos. A mudança 06 confirmou isso na prática.

Descartei mais CPU para o banco porque o desafio é ficar mais barato. Descartei o Redis porque adiciona um serviço e o risco de dado velho, quando o próprio banco ainda tinha desperdício para cortar. Descartei concorrência na API porque ela não reduz o trabalho do banco e aumentaria o número de conexões, que já pesam na memória.

## 6. Experimento e resultado

Cada mudança foi commitada antes de medir. O contrato (42 respostas) foi mantido em todas as medições, e cada valor é a mediana de três execuções. O "antes" de cada linha é a mudança anterior. O "antes" da 01 é um controle: o código original medido com o banco recriado. Ele foi necessário porque o mesmo código ficou mais lento com o banco recriado (3.68 req/s na [linha de base](../resultados/20261111-193058-00-linha-de-base/resumo.txt) contra 2.69 no [controle](../resultados/20261111-202351-00-linha-de-base-banco-recriado/resumo.txt)).

| Mudança | Hipótese | p95 antes → depois | req/s antes → depois | CPU / memória do banco | Pastas de resultados | Conclusão |
|---|---|---|---|---|---|---|
| 01 · índice em pedidos por cliente | Evitar ler todos os pedidos | 26751.0 → 21497.2 ms | 2.69 → 2.93 | 98.2% / 391.1 MiB | [1](../resultados/20261111-200605-01-indice-pedidos-cliente/resumo.txt) [2](../resultados/20261111-200840-01-indice-pedidos-cliente/resumo.txt) [3](../resultados/20261111-201023-01-indice-pedidos-cliente/resumo.txt) | Sem ganho claro |
| 02 · índice em itens por pedido | Evitar ler 1,5 milhão de itens por pedido | 21497.2 → 12529.4 ms | 2.93 → 4.85 | 98.2% / 392.2 MiB | [1](../resultados/20261111-204310-02-indice-itens-pedido/resumo.txt) [2](../resultados/20261111-204442-02-indice-itens-pedido/resumo.txt) [3](../resultados/20261111-204617-02-indice-itens-pedido/resumo.txt) | Ganho |
| 03 · índice em pedidos por status | Página sem ordenar tudo | 12529.4 → 11714.9 ms | 4.85 → 5.27 | 99.5% / 417.2 MiB | [1](../resultados/20261111-205156-03-indice-pedidos-status/resumo.txt) [2](../resultados/20261111-205330-03-indice-pedidos-status/resumo.txt) [3](../resultados/20261111-205505-03-indice-pedidos-status/resumo.txt) | Sem ganho claro |
| 04 · ranking pré-calculado | Não somar todos os itens a cada chamada | 11714.9 → 9635.0 ms | 5.27 → 7.85 | 98.8% / 456.3 MiB | [1](../resultados/20261111-210204-04-top-produtos-materializado/resumo.txt) [2](../resultados/20261111-210331-04-top-produtos-materializado/resumo.txt) [3](../resultados/20261111-210457-04-top-produtos-materializado/resumo.txt) | Ganho |
| 05 · pool de conexões | Não abrir uma conexão por consulta | 9635.0 → 3282.7 ms | 7.85 → 21.50 | 96.6% / 474.2 MiB | [1](../resultados/20261111-211050-05-pool-de-conexoes/resumo.txt) [2](../resultados/20261111-211212-05-pool-de-conexoes/resumo.txt) [3](../resultados/20261111-211335-05-pool-de-conexoes/resumo.txt) | Maior ganho |
| 06 · sem N+1 | 3 consultas em vez de ~22 | 3282.7 → 2216.3 ms | 21.50 → 20.88 | 98.0% / 470.5 MiB | [1](../resultados/20261111-211914-06-sem-n-mais-1/resumo.txt) [2](../resultados/20261111-212038-06-sem-n-mais-1/resumo.txt) [3](../resultados/20261111-212206-06-sem-n-mais-1/resumo.txt) | Parcial: p95 caiu, req/s não |
| 07 · total por status pré-calculado | Não recontar até 300 mil pedidos | 2216.3 → 2404.6 ms | 20.88 → 20.70 | 96.1% / 468.8 MiB | [1](../resultados/20261111-213017-07-contagem-por-status/resumo.txt) [2](../resultados/20261111-213141-07-contagem-por-status/resumo.txt) [3](../resultados/20261111-213305-07-contagem-por-status/resumo.txt) | Sem ganho; hipótese refutada |

A CPU da API subiu de 7.9% no controle para 30.4% depois da 07, porque ela passou a atender mais requisições. Os detalhes de cada mudança estão no [`experimentos.md`](../experimentos.md).

O que não funcionou ensina tanto quanto o resto. A 01 e a 03 aceleraram a consulta, mas atacaram uma parte pequena do trabalho do banco. A 06 deixou a rota mais rápida, mas as outras rotas passaram a esperar mais, porque o total de trabalho do banco quase não mudou. Escolhi a 07 com uma estimativa feita com o banco parado; a medição a refutou. A mesma consulta levou 75.258 ms numa execução e 30.784 ms em outra, então a estimativa era frágil.

## 7. Limites e testes futuros

- **Poucas execuções.** Medi três vezes cada mudança; Chen et al. repetem os testes mais de 30 vezes para lidar com a variação [9]. Por isso trato como "sem ganho claro" diferenças pequenas que caem dentro da faixa das execuções anteriores.
- **Diferença não explicada.** O mesmo código ficou mais lento depois de recriar o banco. Não sei se a causa é o banco recém-criado ou a máquina ao longo da noite.
- **Dados que não mudam.** As visões materializadas funcionam porque esta API só lê. Com pedidos novos, ficariam desatualizadas sem `REFRESH` [10].
- **Memória do banco.** A média chegou a 474.2 MiB na 05, com pico de 501.1 MiB na 07, perto do limite de 512 MB. Não verifiquei a causa.
- **O que derrubaria a conclusão principal:** medir, com `pg_stat_statements` [12], que o banco gasta pouco tempo com conexões depois do pool. Aí o ganho da 05 teria outra explicação.

As ideias pesquisadas e não testadas (consultas paralelas no banco, índice para e-mail, reescrever `vendas-por-dia`, cache, concorrência e paginação sem `OFFSET` [13]) estão no [`proximos-testes.md`](../proximos-testes.md).

## 8. Referências

Todas acessadas em 18/11/2026.

1. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.4. Indexes and ORDER BY*. https://www.postgresql.org/docs/16/indexes-ordering.html
2. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 14.1. Using EXPLAIN*. https://www.postgresql.org/docs/16/using-explain.html
3. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 11.7. Indexes on Expressions*. https://www.postgresql.org/docs/16/indexes-expressional.html
4. Yang, J.; Subramaniam, P.; Lu, S.; Yan, C.; Cheung, A. *How not to structure your database-backed web applications: a study of performance bugs in the wild*. ICSE 2018. https://par.nsf.gov/servlets/purl/10067547 (DOI 10.1145/3180155.3180194)
5. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 52.2. How Connections Are Established*. https://www.postgresql.org/docs/16/connect-estab.html
6. node-postgres. *Pooling*. https://node-postgres.com/features/pooling
7. Freund, A. *Analyzing the Limits of Connection Scalability in Postgres*. Citus Data / Microsoft, 2020. https://www.citusdata.com/blog/2020/10/08/analyzing-connection-scalability/
8. Heroku Dev Center. *Server-Side Connection Pooling for Heroku Postgres*. https://devcenter.heroku.com/articles/postgres-connection-pooling
9. Chen, T.-H.; Shang, W.; Jiang, Z. M.; Hassan, A. E.; Nasser, M.; Flora, P. *Detecting Performance Anti-patterns for Applications Developed using Object-Relational Mapping*. ICSE 2014. https://ece.uwaterloo.ca/~wshang/pubs/peter_icse2014.pdf
10. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, 41.3. Materialized Views*. https://www.postgresql.org/docs/16/rules-materializedviews.html
11. Redis. *Redis cache-aside*. https://redis.io/docs/latest/develop/use-cases/cache-aside/
12. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation, F.32. pg_stat_statements*. https://www.postgresql.org/docs/16/pgstatstatements.html
13. Winand, M. *We need tool support for keyset pagination*. Use The Index, Luke. https://use-the-index-luke.com/no-offset

## 9. Uso de IA

Usei o Claude Code (Anthropic) em quase todo o trabalho: para explicar o código, propor e implementar as mudanças, rodar as medições, buscar e ler as fontes, e redigir o `experimentos.md`, o `proximos-testes.md` e este artigo. Eu conduzi as etapas, decidi o que aceitar, fiz os commits (exceto dois feitos pela IA, marcados com `Co-Authored-By` no histórico) e revisei os textos. Para verificar: todo número vem dos arquivos gerados pelo `medir.sh` em `resultados/` ou das saídas salvas em `diagnostico/`; o contrato foi conferido a cada mudança; e abri cada link das referências antes da entrega.
