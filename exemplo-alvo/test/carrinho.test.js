const test = require('node:test');
const assert = require('node:assert/strict');
const { calcularTotal } = require('../src/carrinho');

const item = (preco, quantidade = 1) => ({ preco, quantidade });

test('calcula carrinhos e aceita propriedades extras', () => {
  for (const [itens, esperado] of [
    [[], 0], [[item(10)], 10], [[item(10, 2), item(5, 3)], 35],
    [[item(10, 0)], 0], [[item(0, 5)], 0], [[item(2.5, 4)], 10],
    [[item(4, 2.5)], 10], [[{ ...item(3), nome: 'produto' }], 3],
  ]) {
    assert.equal(calcularTotal(itens), esperado);
  }
});

test('arredonda somente no final e retorna number', () => {
  for (const [itens, cupom, esperado] of [
    [[item(0.1, 3)], undefined, 0.3],
    [[item(1.005)], undefined, 1.01],
    [[item(10.005)], undefined, 10.01],
    [[item(0.004), item(0.004)], undefined, 0.01],
    [[item(10)], { tipo: 'percentual', valor: 33.333 }, 6.67],
  ]) {
    const resultado = calcularTotal(itens, cupom);
    assert.equal(resultado, esperado);
    assert.equal(typeof resultado, 'number');
  }
});

test('aplica cupons e normaliza zero positivo', () => {
  assert.equal(calcularTotal([item(10)]), 10);
  for (const cupom of [undefined, null]) assert.equal(calcularTotal([item(10)], cupom), 10);
  for (const [tipo, valor, esperado] of [
    ['percentual', 0, 10], ['percentual', 10, 9], ['percentual', 100, 0],
    ['fixo', 3, 7], ['fixo', 10, 0], ['fixo', 20, 0],
  ]) {
    const resultado = calcularTotal([item(10)], { tipo, valor });
    assert.equal(resultado, esperado);
    if (esperado === 0) assert.ok(Object.is(resultado, 0));
  }
  assert.ok(Object.is(calcularTotal([item(-0, -0)]), 0));
  assert.ok(Object.is(calcularTotal([]), 0));
});

test('rejeita itens e campos com tipos inválidos', () => {
  for (const itens of [undefined, null, {}, 'itens', 10]) {
    assert.throws(() => calcularTotal(itens), TypeError);
  }
  for (const invalido of [null, undefined, 10, 'item', true, []]) {
    assert.throws(() => calcularTotal([invalido]), TypeError);
  }
  assert.throws(() => calcularTotal(new Array(1)), TypeError);
  for (const campo of ['preco', 'quantidade']) {
    for (const valor of [undefined, null, '10', NaN, Infinity, -Infinity]) {
      assert.throws(() => calcularTotal([{ ...item(10), [campo]: valor }]), TypeError);
    }
    const incompleto = item(10);
    delete incompleto[campo];
    assert.throws(() => calcularTotal([incompleto]), TypeError);
    assert.throws(() => calcularTotal([{ ...item(10), [campo]: -1 }]), RangeError);
  }
  assert.throws(() => calcularTotal([item(1), item('10')]), /itens\[1\]\.preco/);
});

test('valida cupom mesmo com carrinho vazio', () => {
  for (const cupom of [10, 'cupom', true, [], {}, { tipo: 'outro', valor: 1 }]) {
    assert.throws(() => calcularTotal([], cupom), TypeError);
  }
  for (const tipo of ['fixo', 'percentual']) {
    for (const valor of [undefined, null, '10', NaN, Infinity, -Infinity]) {
      assert.throws(() => calcularTotal([], { tipo, valor }), TypeError);
    }
    assert.throws(() => calcularTotal([], { tipo, valor: -1 }), RangeError);
  }
  assert.throws(() => calcularTotal([], { tipo: 'percentual', valor: 100.01 }), RangeError);
});

test('rejeita overflow no produto e na soma do subtotal', () => {
  assert.throws(() => calcularTotal([item(Number.MAX_VALUE, 2)]), RangeError);
  assert.throws(() => calcularTotal([item(Number.MAX_VALUE), item(Number.MAX_VALUE)]), RangeError);
});

test('não altera entradas e aceita objetos congelados', () => {
  const itens = [{ ...item(10, 2), nome: 'produto' }];
  const cupom = { tipo: 'percentual', valor: 10 };
  const copia = structuredClone({ itens, cupom });
  assert.equal(calcularTotal(itens, cupom), 18);
  assert.deepStrictEqual({ itens, cupom }, copia);
  Object.freeze(itens[0]);
  Object.freeze(itens);
  Object.freeze(cupom);
  assert.equal(calcularTotal(itens, cupom), 18);
  assert.deepStrictEqual({ itens, cupom }, copia);
});

test('estouro após a validação lança RangeError, com ou sem cupom', () => {
  assert.throws(() => calcularTotal([item(1e307)]), RangeError);
  assert.throws(() => calcularTotal([item(1e307)], { tipo: 'percentual', valor: 50 }), RangeError);
  assert.equal(calcularTotal([item(1e307)], { tipo: 'fixo', valor: 1e307 }), 0); // 1e307 - 1e307 é legítimo
});

test('getters que mudam de valor não burlam a validação (leitura única)', () => {
  let leituras = 0;
  const instavel = { quantidade: 1, get preco() { leituras += 1; return leituras === 1 ? 10 : -100; } };
  assert.equal(calcularTotal([instavel]), 10);

  let tipoLido = 0;
  const cupomInstavel = { valor: 10, get tipo() { tipoLido += 1; return tipoLido === 1 ? 'percentual' : 'invalido'; } };
  assert.equal(calcularTotal([item(100)], cupomInstavel), 90);
});

test('documenta o limite de precisão dos centavos (~1e13)', () => {
  assert.equal(calcularTotal([item(1e14 + 0.005)]), 1e14);
  assert.equal(calcularTotal([item(10.005)]), 10.01);
});

test('propriedades herdadas são aceitas (comportamento documentado)', () => {
  assert.equal(calcularTotal([Object.create({ preco: 5, quantidade: 2 })]), 10);
});

test('preserva as mensagens de validação de calcularTotal', () => {
  for (const [cupom, name, message] of [
    [true, 'TypeError', 'cupom precisa ser um objeto'],
    [{ tipo: 'outro', valor: 1 }, 'TypeError', 'cupom.tipo precisa ser percentual ou fixo'],
    [{ tipo: 'fixo', valor: NaN }, 'TypeError', 'cupom.valor precisa ser um número finito'],
    [{ tipo: 'fixo', valor: -1 }, 'RangeError', 'cupom.valor precisa ser maior ou igual a zero'],
    [{ tipo: 'percentual', valor: 101 }, 'RangeError', 'cupom.valor percentual não pode passar de 100'],
  ]) assert.throws(() => calcularTotal([], cupom), { name, message });
});

const { listarCuponsValidos } = require('../src/carrinho');
const cupomDatado = (codigo = 'A', validoAte = '2026-11-13') => ({ codigo, tipo: 'fixo', valor: 1, validoAte });

test('filtra pela borda inclusiva, ordena com estabilidade e preserva referências', () => {
  const a = Object.freeze({ ...cupomDatado('A', new Date('2026-11-14')), extra: true });
  const b = Object.freeze(cupomDatado('B', '2026-11-13T03:00:00-03:00'));
  const c = Object.freeze(cupomDatado('C', '2026-11-13T06:00Z'));
  const cupons = Object.freeze([a, b, cupomDatado('vencido'), c]);
  const resultado = listarCuponsValidos(cupons, new Date('2026-11-13T06:00Z'));
  assert.deepEqual(resultado, [b, c, a]);
  assert.equal(resultado[0], b);
  assert.equal(resultado[2], a);
  assert.equal(resultado[2].extra, true);
  assert.notEqual(resultado, cupons);
  assert.equal(cupons[0], a);
  const vazio = [];
  assert.deepEqual(listarCuponsValidos(vazio, '2026-11-13'), []);
  assert.notEqual(listarCuponsValidos(vazio, '2026-11-13'), vazio);
  assert.deepEqual(listarCuponsValidos([cupomDatado()], '2026-11-13'), [cupomDatado()]);
});

test('valida lista, objetos e todos os campos, inclusive em cupons vencidos', () => {
  for (const entrada of [undefined, null, {}, 'cupons', 1]) {
    assert.throws(() => listarCuponsValidos(entrada, '2026-11-13'), TypeError);
  }
  for (const entrada of [null, undefined, [], true, 1, 'cupom']) {
    assert.throws(() => listarCuponsValidos([entrada], '2026-11-13'), /cupons\[0\]/);
  }
  assert.throws(() => listarCuponsValidos(new Array(1), '2026-11-13'), TypeError);
  for (const [campo, valores, Erro] of [
    ['tipo', [undefined, 'outro', null], TypeError],
    ['valor', [undefined, null, '1', NaN, Infinity, -Infinity], TypeError],
    ['valor', [-1], RangeError],
    ['codigo', [undefined, null, 1, {}], TypeError],
    ['codigo', ['', '  \t'], RangeError],
  ]) {
    for (const valor of valores) {
      assert.throws(() => listarCuponsValidos([{ ...cupomDatado(), [campo]: valor }], '2027-01-01'), Erro);
    }
  }
  assert.throws(() => listarCuponsValidos([{ ...cupomDatado(), tipo: 'percentual', valor: 101 }], '2026-11-13'), RangeError);
});

test('valida datas ISO e Date em hoje e validoAte', () => {
  const falso = Object.create(Date.prototype);
  for (const [datas, Erro] of [
    [[undefined, null, 1, {}, false, falso, { getTime: () => 0 }], TypeError],
    [['', 'Nov 13 2026', '2026-02-30', '1900-02-29', '2026-02-29', '2026-00-01', '2026-13-01',
      '2026-01-00', '2026-04-31', '2026-11-13T10:00', '2026-11-13T25:00Z',
      '2026-11-13T23:60Z', '2026-11-13T10:00+25:00', new Date(NaN)], RangeError],
  ]) {
    for (const data of datas) {
      assert.throws(() => listarCuponsValidos([], data), Erro);
      assert.throws(() => listarCuponsValidos([{ ...cupomDatado(), validoAte: data }], '2026-11-13'), Erro);
    }
  }
  for (const data of ['2000-02-29', '2024-02-29', '2026-11-13T24:00Z', '2026-11-13T10:00:00.123Z']) {
    assert.equal(listarCuponsValidos([cupomDatado('A', data)], data).length, 1);
  }
  const sobrescrita = new Date('2026-11-13');
  sobrescrita.getTime = () => NaN;
  assert.equal(listarCuponsValidos([cupomDatado('A', sobrescrita)], '2026-11-13').length, 1);
  assert.throws(() => listarCuponsValidos([], require('node:vm').runInNewContext('new Date()')), TypeError);
});

test('lê cada campo uma vez e usa a data validada para filtrar e ordenar', () => {
  const leituras = {};
  const instavel = {};
  for (const [campo, valor] of Object.entries(cupomDatado())) {
    Object.defineProperty(instavel, campo, { get() {
      leituras[campo] = (leituras[campo] || 0) + 1;
      return leituras[campo] === 1 ? valor : null;
    } });
  }
  const resultado = listarCuponsValidos([cupomDatado('B', '2026-11-14'), instavel], '2026-11-13');
  assert.equal(resultado[0], instavel);
  assert.deepEqual(leituras, { tipo: 1, valor: 1, codigo: 1, validoAte: 1 });
});

const { calcularFrete } = require('../src/carrinho');

test('frete cobra a tarifa fixa até 1 kg e aceita zero negativo', () => {
  for (const [peso, distanciaKm] of [
    [0, 0], [0.5, 0], [1, 0], [-0, 0], [Number.MIN_VALUE, Number.MIN_VALUE],
  ]) {
    assert.ok(Object.is(calcularFrete(peso, distanciaKm), 5));
  }
});

test('frete soma peso excedente e distância e retorna number', () => {
  for (const [peso, distanciaKm, esperado] of [
    [2, 0, 5.8], [3.5, 0, 7], [1, 10, 6], [1, 100, 15],
    [2.5, 15, 7.7], [1.333, 10.333, 6.3], [1e12, 1e12, 900000000004.2],
  ]) {
    const resultado = calcularFrete(peso, distanciaKm);
    assert.equal(resultado, esperado);
    assert.equal(typeof resultado, 'number');
  }
});

test('frete arredonda o resultado em duas casas', () => {
  for (const [peso, distanciaKm] of [[1.01, 0], [1.00625, 0], [1, 0.05]]) {
    assert.equal(calcularFrete(peso, distanciaKm), 5.01);
  }
});

test('frete rejeita tipos inválidos e números não finitos nos dois parâmetros', () => {
  for (const valor of ['10', null, undefined, {}, [], true, NaN, Infinity, -Infinity, 1n]) {
    assert.throws(() => calcularFrete(valor, 0), TypeError);
    assert.throws(() => calcularFrete(1, valor), TypeError);
  }
});

test('frete rejeita valores negativos nos dois parâmetros', () => {
  for (const valor of [-0.1, -5, -Number.MIN_VALUE]) {
    assert.throws(() => calcularFrete(valor, 0), RangeError);
    assert.throws(() => calcularFrete(1, valor), RangeError);
  }
});

test('frete rejeita estouro e aceita valor grande que não estoura', () => {
  for (const [peso, distanciaKm] of [[1e307, 0], [Number.MAX_VALUE, 0], [0, Number.MAX_VALUE]]) {
    assert.throws(() => calcularFrete(peso, distanciaKm), {
      name: 'RangeError', message: 'valores grandes demais para calcular o frete',
    });
  }
  assert.equal(calcularFrete(0, 1e307), 1e306);
});

test('frete preserva as mensagens de validação dos parâmetros', () => {
  for (const [peso, distanciaKm, name, message] of [
    [NaN, 0, 'TypeError', 'peso precisa ser um número finito'],
    [1, NaN, 'TypeError', 'distanciaKm precisa ser um número finito'],
    [-1, 0, 'RangeError', 'peso precisa ser maior ou igual a zero'],
    [1, -1, 'RangeError', 'distanciaKm precisa ser maior ou igual a zero'],
  ]) assert.throws(() => calcularFrete(peso, distanciaKm), { name, message });
});

test('exporta calcularFrete e mantém as funções existentes', () => {
  const carrinho = require('../src/carrinho');
  assert.equal(typeof carrinho.calcularFrete, 'function');
  assert.equal(carrinho.calcularTotal, calcularTotal);
  assert.equal(carrinho.listarCuponsValidos, listarCuponsValidos);
});
