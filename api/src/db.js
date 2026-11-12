const { Pool } = require('pg');

// Pool de conexões: mantém até 10 conexões abertas com o banco e as reaproveita,
// em vez de abrir e fechar uma conexão a cada consulta.
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || 'loja',
  database: process.env.DB_NAME || 'loja',
  max: 10,
});

// Sem este tratador, um erro numa conexão parada no pool (ex.: banco reiniciado) derrubaria a API.
pool.on('error', (erro) => {
  console.error('erro numa conexao parada do pool', erro);
});

async function consultar(sql, parametros = []) {
  const resultado = await pool.query(sql, parametros);
  return resultado.rows;
}

module.exports = { consultar };
