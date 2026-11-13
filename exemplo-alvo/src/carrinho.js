function validarNumero(valor, caminho) {
  if (typeof valor !== 'number' || !Number.isFinite(valor)) {
    throw new TypeError(`${caminho} precisa ser um número finito`);
  }
  if (valor < 0) {
    throw new RangeError(`${caminho} precisa ser maior ou igual a zero`);
  }
}

function validarItens(itens) {
  if (!Array.isArray(itens)) {
    throw new TypeError('itens precisa ser um array');
  }
  // Cada campo é lido uma única vez; o cálculo usa estas cópias validadas (getters não burlam a validação).
  return Array.from(itens, (item, i) => { // Array.from não pula posições vazias (arrays esparsos)
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      throw new TypeError(`itens[${i}] precisa ser um objeto`);
    }
    const { preco, quantidade } = item;
    validarNumero(preco, `itens[${i}].preco`);
    validarNumero(quantidade, `itens[${i}].quantidade`);
    return { preco, quantidade };
  });
}

function validarCupom(cupom, caminho = 'cupom') {
  if (cupom == null) return null;
  if (typeof cupom !== 'object' || Array.isArray(cupom)) {
    throw new TypeError(`${caminho} precisa ser um objeto`);
  }
  const { tipo, valor } = cupom; // leitura única
  if (tipo !== 'percentual' && tipo !== 'fixo') {
    throw new TypeError(`${caminho}.tipo precisa ser percentual ou fixo`);
  }
  validarNumero(valor, `${caminho}.valor`);
  if (tipo === 'percentual' && valor > 100) {
    throw new RangeError(`${caminho}.valor percentual não pode passar de 100`);
  }
  return { tipo, valor };
}

const arredondar2 = (valor) => Math.round(Number((valor * 100).toPrecision(15))) / 100;

function calcularTotal(itens, cupom) {
  const itensValidos = validarItens(itens);
  const cupomValido = validarCupom(cupom);
  const subtotal = itensValidos.reduce((total, item) => total + item.preco * item.quantidade, 0);
  if (!Number.isFinite(subtotal)) {
    throw new RangeError('subtotal precisa ser finito');
  }
  let desconto = 0;
  if (cupomValido != null) {
    desconto = cupomValido.tipo === 'percentual' ? subtotal * cupomValido.valor / 100 : cupomValido.valor;
  }
  // Estouro depois da validação nunca pode ser escondido pelo piso em zero.
  const liquido = subtotal - desconto;
  if (!Number.isFinite(desconto) || !Number.isFinite(liquido) || !Number.isFinite(liquido * 100)) {
    throw new RangeError('valores grandes demais para calcular o total');
  }
  return arredondar2(Math.max(0, liquido)) + 0;
}

// Frete: 5 fixo + 0,8 por kg acima de 1 kg + 0,1 por km.
function calcularFrete(peso, distanciaKm) {
  validarNumero(peso, 'peso');
  validarNumero(distanciaKm, 'distanciaKm');
  const total = 5 + Math.max(0, peso - 1) * 0.8 + distanciaKm * 0.1;
  if (!Number.isFinite(total) || !Number.isFinite(total * 100)) {
    throw new RangeError('valores grandes demais para calcular o frete');
  }
  return arredondar2(Math.max(0, total)) + 0;
}

function validarData(data, caminho) {
  let ms;
  if (data instanceof Date) {
    ms = Date.prototype.getTime.call(data);
  } else if (typeof data === 'string') {
    // Horários exigem fuso explícito; datas sem horário representam meia-noite UTC.
    const partes = /^(\d{4})-(\d{2})-(\d{2})(?:T\d{2}:\d{2}(?::\d{2}(?:\.\d{3})?)?(?:Z|[+-]\d{2}:\d{2}))?$/.exec(data);
    if (!partes) throw new RangeError(`${caminho} precisa ser uma data ISO válida`);
    const ano = Number(partes[1]);
    const mes = Number(partes[2]);
    const dia = Number(partes[3]);
    const bissexto = ano % 4 === 0 && (ano % 100 !== 0 || ano % 400 === 0);
    const diasPorMes = [31, bissexto ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (mes < 1 || mes > 12 || dia < 1 || dia > diasPorMes[mes - 1]) {
      throw new RangeError(`${caminho} precisa ser uma data ISO válida`);
    }
    ms = Date.parse(data);
  } else {
    throw new TypeError(`${caminho} precisa ser Date ou string ISO`);
  }
  if (!Number.isFinite(ms)) throw new RangeError(`${caminho} precisa ser uma data válida`);
  return ms;
}

function listarCuponsValidos(cupons, hoje) {
  if (!Array.isArray(cupons)) throw new TypeError('cupons precisa ser um array');
  const hojeMs = validarData(hoje, 'hoje');
  return Array.from(cupons, (cupom, i) => {
    const caminho = `cupons[${i}]`;
    if (cupom === null || typeof cupom !== 'object' || Array.isArray(cupom)) {
      throw new TypeError(`${caminho} precisa ser um objeto`);
    }
    validarCupom(cupom, caminho);
    const { codigo, validoAte } = cupom;
    if (typeof codigo !== 'string') throw new TypeError(`${caminho}.codigo precisa ser uma string`);
    if (codigo.trim() === '') throw new RangeError(`${caminho}.codigo não pode ser vazio`);
    return { cupom, ms: validarData(validoAte, `${caminho}.validoAte`) };
  }).filter(({ ms }) => ms >= hojeMs)
    .sort((a, b) => a.ms - b.ms)
    .map(({ cupom }) => cupom);
}

module.exports = { calcularTotal, listarCuponsValidos, calcularFrete };
