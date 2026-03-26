import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ocrScriptPath = path.join(__dirname, "ocr.swift");

const excludedSymbolTokens = new Set([
  "KRW",
  "USD",
  "USDT",
  "USDC",
  "ETF",
  "PER",
  "PBR",
  "NAV",
  "CMA",
  "MMF"
]);

const cryptoSymbols = new Set([
  "BTC",
  "ETH",
  "XRP",
  "SOL",
  "ADA",
  "DOGE",
  "TRX",
  "AVAX",
  "BNB",
  "ATOM",
  "DOT",
  "LINK",
  "MATIC"
]);

const stablecoinSymbols = new Set(["USDT", "USDC"]);

const imageTypeSignals = {
  crypto: ["업비트", "OKX", "코인", "거래소", "현물", "선물", "BTC", "ETH", "USDT"],
  foreignStock: ["해외주식", "미국주식", "NASDAQ", "NYSE", "AAPL", "SCHD", "QQQ", "VOO"],
  domesticStock: ["국내주식", "삼성전자", "코스피", "코스닥", "영웅문", "주식잔고"],
  cashEquivalent: ["예수금", "잔고", "출금가능", "계좌잔액", "보통예금", "현금", "외화예수금", "외화추정예수금", "D2예수금", "외화자산"],
  bond: ["채권", "국채", "회사채", "TREASURY", "BOND"]
};

const fallbackKRWRates = {
  USD: 1472.3,
  USDT: 1471.8
};

const openAIAPIKey = process.env.OPENAI_API_KEY ?? "";
const openAIBaseURL = String(process.env.OPENAI_BASE_URL ?? "https://api.openai.com/v1").replace(/\/+$/, "");
const openAIModel = process.env.OPENAI_MODEL ?? "gpt-5.4-mini";
const openAIReasoningEffort = process.env.OPENAI_REASONING_EFFORT ?? "low";
const configuredAnalysisProvider = String(process.env.MYPORT_ANALYSIS_PROVIDER ?? "").trim().toLowerCase();
const analysisProvider = resolveAnalysisProvider(configuredAnalysisProvider);

const portfolioAnalysisSchema = {
  type: "object",
  properties: {
    institutions: {
      type: "array",
      items: { type: "string" },
      maxItems: 10
    },
    previewLines: {
      type: "array",
      items: { type: "string" },
      maxItems: 20
    },
    recognizedLineCount: {
      type: "integer"
    },
    explicitRates: {
      type: "array",
      items: {
        type: "object",
        properties: {
          baseCurrency: { type: "string" },
          rateToKRW: { type: "number" },
          sourceText: { type: "string" }
        },
        required: ["baseCurrency", "rateToKRW", "sourceText"],
        additionalProperties: false
      }
    },
    holdings: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          symbol: { type: "string" },
          institution: { type: "string" },
          assetClass: {
            type: "string",
            enum: [
              "domesticStock",
              "foreignStock",
              "cashEquivalent",
              "crypto",
              "bond",
              "unknown"
            ]
          },
          quantity: {
            type: ["number", "null"]
          },
          unitPrice: {
            type: ["number", "null"]
          },
          marketValue: { type: "number" },
          currency: { type: "string" },
          country: { type: "string" },
          memo: { type: "string" }
        },
        required: [
          "name",
          "symbol",
          "institution",
          "assetClass",
          "quantity",
          "unitPrice",
          "marketValue",
          "currency",
          "country",
          "memo"
        ],
        additionalProperties: false
      }
    }
  },
  required: [
    "institutions",
    "previewLines",
    "recognizedLineCount",
    "explicitRates",
    "holdings"
  ],
  additionalProperties: false
};

const openAIInstructions = [
  "You extract portfolio holdings from mobile finance screenshots.",
  "Return only the data required by the JSON schema.",
  "Classify each holding as one of: domesticStock, foreignStock, cashEquivalent, crypto, bond, unknown.",
  "Prefer individual holdings over summary totals when both exist.",
  "Keep currencies exactly as shown when possible, such as KRW, USD, or USDT.",
  "Use cashEquivalent for 예수금, 외화예수금, 외화추정예수금, D2예수금, 외화잔고, 현금, 계좌잔액, 보통예금, CMA, MMF, and stablecoin balances like USDT or USDC.",
  "Use foreignStock for US or other overseas equities and ETFs, domesticStock for KR equities and ETFs, crypto for BTC/ETH and other coins, and bond for 국채/회사채/채권 products.",
  "If the screenshot contains Super365, treat the institution as 메리츠증권.",
  "If the screenshot shows the top tabs 투자, 연금/ISA, CMA, 예적금 together with bottom tabs like 국내현재가, 국내주문, 국내잔고, treat the institution as 우리투자증권.",
  "Preserve foreign-currency cash balances as separate cashEquivalent holdings, including currencies like USD, CHF, EUR, JPY, HKD, CNY, and GBP.",
  "When a cash balance uses Swiss francs or mentions 스위스프랑, use currency CHF.",
  "For 메리츠증권 Super365 domestic stock balance screens, rows like 현대차, 삼성전자, LS ELECTRIC with 현금 and 1주 are stock holdings. 현금 there is a settlement label, not a cashEquivalent asset.",
  "For 메리츠증권 Super365 예수금 screens, include positive KRW cash balances such as 추정예수금(D+1), 추정예수금(D+2), 출금가능금액, and 주문가능금액(현금). Redundant zero-only rows may be omitted.",
  "Do not create cashEquivalent holdings from stock summary labels such as 내 주식, 주식평가금액(A), 평가금액(A), 순평가(A-B), or from stock settlement labels like 현금 • 1주 or 현금 | AGIX. Those belong to stock holdings screens, not cash balances.",
  "If a screenshot shows a derived portfolio app result rather than an original brokerage or exchange screen, ignore it unless no original source screenshots are available. Derived app screens often include navigation tabs such as 대시보드, 업로드, 히스토리, 설정, Dashboard, Upload, History, or Settings.",
  "If the screenshot contains 키움, 키움전체, 영웅문, 해외잔고, or [위탁종합], treat the institution as 키움증권. Do not label those screens as KB증권 unless KB branding is explicitly visible.",
  "For 키움증권 해외잔고 tables, 매입금액 and 평가금액 are total position amounts for the holding, not per-share prices. Never multiply those displayed amounts by quantity. If only total amounts are visible, set unitPrice to null.",
  "If a quantity is missing, set quantity to null.",
  "If a unit price is missing or the visible number is a total position amount rather than a per-share price, set unitPrice to null.",
  "For each holding memo, include a short raw source snippet with the visible row labels and numbers when possible, for example: row: QLD / 수량 70 / 매입금액 3779.5386 / 평가금액 4466.0560.",
  "Set previewLines to short snippets that help a user review the extraction.",
  "Only include explicitRates when the screenshot itself clearly shows an FX rate."
].join(" ");

export function getAnalysisRuntimeInfo() {
  return {
    provider: analysisProvider,
    model: analysisProvider === "openai" ? openAIModel : null,
    openAIConfigured: openAIAPIKey.length > 0
  };
}

export async function analyzeUploadSession(uploadSession) {
  const analysis = await analyzeFiles(uploadSession.files ?? []);
  const exchangeRates = await buildExchangeRates({
    capturedAt: uploadSession.capturedAt,
    explicitRates: analysis.explicitRates,
    currencies: new Set(analysis.holdings.map((holding) => holding.currency))
  });

  const titlePrefix = analysis.institutions.length > 0
    ? analysis.institutions.join(", ")
    : "자동 분석";
  const note = buildAnalysisNote({
    imageCount: uploadSession.files.length,
    analysis,
    exchangeRates,
    provider: analysisProvider
  });

  return {
    snapshot: {
      id: randomUUID(),
      title: `${titlePrefix} ${String(uploadSession.capturedAt).slice(0, 16).replace("T", " ")}`,
      capturedAt: uploadSession.capturedAt,
      note,
      createdAt: new Date().toISOString(),
      baseCurrency: "KRW",
      holdings: analysis.holdings,
      exchangeRates,
      lastSyncedAt: new Date().toISOString()
    },
    metadata: {
      institutions: analysis.institutions,
      recognizedLineCount: analysis.recognizedLineCount,
      parsedHoldingCount: analysis.holdings.length
    }
  };
}

async function analyzeFiles(files) {
  if (analysisProvider === "openai") {
    return analyzeImagesWithOpenAI(files);
  }

  if (analysisProvider === "vision") {
    const imagePaths = files.map((file) => file.filePath);
    const ocrResults = await runOCR(imagePaths);
    return analyzeOCRResults(ocrResults);
  }

  throw new Error(`지원하지 않는 분석 공급자입니다: ${analysisProvider}`);
}

async function runOCR(imagePaths) {
  if (imagePaths.length === 0) {
    return [];
  }

  const { stdout } = await execFileAsync(
    "swift",
    [ocrScriptPath, ...imagePaths],
    {
      maxBuffer: 20 * 1024 * 1024
    }
  );

  const parsed = JSON.parse(stdout);
  return Array.isArray(parsed) ? parsed : [];
}

async function analyzeImagesWithOpenAI(files) {
  if (files.length === 0) {
    return {
      holdings: [],
      explicitRates: new Map([["KRW", 1]]),
      institutions: [],
      recognizedLineCount: 0,
      previewLines: []
    };
  }

  if (openAIAPIKey.length === 0) {
    throw new Error("OPENAI_API_KEY가 설정되지 않아 OpenAI 이미지 분석을 실행할 수 없습니다.");
  }

  const content = [
    {
      type: "input_text",
      text: "Analyze these portfolio screenshots and extract holdings into the provided schema."
    }
  ];

  for (const file of files) {
    content.push({
      type: "input_image",
      image_url: await buildImageDataURL(file)
    });
  }

  const body = {
    model: openAIModel,
    instructions: openAIInstructions,
    input: [
      {
        role: "user",
        content
      }
    ],
    text: {
      format: {
        type: "json_schema",
        name: "portfolio_screenshot_analysis",
        schema: portfolioAnalysisSchema,
        strict: true
      }
    }
  };

  if (supportsReasoning(openAIModel)) {
    body.reasoning = {
      effort: openAIReasoningEffort
    };
  }

  const response = await fetch(`${openAIBaseURL}/responses`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIAPIKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(120_000)
  });

  const payload = await response.json().catch(() => null);

  if (response.ok === false) {
    const message = payload?.error?.message ?? response.statusText;
    throw new Error(`OpenAI 이미지 분석 요청이 실패했습니다. (${response.status}) ${message}`);
  }

  const outputText = extractResponseOutputText(payload);
  if (outputText.length === 0) {
    throw new Error("OpenAI 응답에서 구조화된 분석 결과를 찾지 못했습니다.");
  }

  let parsed;
  try {
    parsed = JSON.parse(outputText);
  } catch (error) {
    throw new Error(
      `OpenAI 응답 JSON을 해석하지 못했습니다: ${error instanceof Error ? error.message : "알 수 없는 오류"}`
    );
  }

  return normalizeOpenAIAnalysis(parsed);
}

async function buildImageDataURL(file) {
  const buffer = await readFile(file.filePath);
  const mimeType = normalizeMimeType(file.mimeType, file.filePath);
  return `data:${mimeType};base64,${buffer.toString("base64")}`;
}

function extractResponseOutputText(payload) {
  if (typeof payload?.output_text === "string" && payload.output_text.trim().length > 0) {
    return payload.output_text.trim();
  }

  const messages = Array.isArray(payload?.output) ? payload.output : [];
  const parts = [];

  for (const message of messages) {
    if (message?.type !== "message" || Array.isArray(message.content) === false) {
      continue;
    }

    for (const content of message.content) {
      if (content?.type === "output_text" && typeof content.text === "string") {
        parts.push(content.text);
      }
    }
  }

  return parts.join("\n").trim();
}

function normalizeOpenAIAnalysis(result) {
  const previewLines = normalizePreviewLines(result?.previewLines);
  const explicitRates = new Map([["KRW", 1]]);
  const institutions = new Set(
    (Array.isArray(result?.institutions) ? result.institutions : [])
      .map((value) => normalizeInstitutionName(value))
      .filter((value) => value.length > 0)
  );
  const analysisContext = buildOpenAIAnalysisContext({
    institutions: Array.from(institutions),
    previewLines
  });

  reconcileInstitutionHints(institutions, analysisContext);

  if (analysisContext.primaryInstitution.length > 0) {
    institutions.add(analysisContext.primaryInstitution);
  }

  for (const item of Array.isArray(result?.explicitRates) ? result.explicitRates : []) {
    const currency = String(item?.baseCurrency ?? "").trim().toUpperCase();
    const rate = toNullableFiniteNumber(item?.rateToKRW);
    if (currency.length === 0 || rate == null || rate <= 0) {
      continue;
    }
    explicitRates.set(currency, rate);
  }

  const holdings = dedupeHoldings(
    (Array.isArray(result?.holdings) ? result.holdings : [])
      .map((holding) => normalizeOpenAIHolding(holding, analysisContext))
      .filter((holding) => holding != null)
  );

  return {
    holdings,
    explicitRates,
    institutions: Array.from(institutions).sort(),
    recognizedLineCount: normalizeCount(result?.recognizedLineCount, result?.previewLines),
    previewLines
  };
}

function normalizeOpenAIHolding(holding, analysisContext) {
  const rawName = cleanupAssetName(String(holding?.name ?? "").trim());
  const symbol = String(holding?.symbol ?? "").trim().toUpperCase();
  const memo = String(holding?.memo ?? "").trim();
  const currency = normalizeHoldingCurrency({
    rawCurrency: holding?.currency,
    rawName,
    memo,
    symbol
  });
  const quantity = toNullableFiniteNumber(holding?.quantity);
  const rawUnitPrice = toNullableFiniteNumber(holding?.unitPrice);
  const rawMarketValue = toNullableFiniteNumber(holding?.marketValue);

  if (rawName.length === 0 || rawMarketValue == null || rawMarketValue <= 0) {
    return null;
  }

  const inferredAssetClass = inferAssetClass(
    `${rawName} ${symbol} ${memo}`.trim(),
    "unknown",
    currency,
    symbol
  );
  const assetClass = normalizeHoldingAssetClass(
    normalizeAssetClass(holding?.assetClass, inferredAssetClass),
    {
      rawName,
      symbol,
      memo,
      currency,
      analysisContext
    }
  );
  const name = normalizeHoldingName({
    rawName,
    assetClass,
    currency,
    memo,
    symbol
  });

  if (shouldDiscardOpenAIHolding({
    rawName,
    normalizedName: name,
    symbol,
    memo,
    assetClass,
    analysisContext
  })) {
    return null;
  }

  const country = normalizeCountry(holding?.country, assetClass, currency);
  const institution = normalizeOpenAIInstitution(holding?.institution, {
    analysisContext,
    assetClass,
    currency,
    symbol,
    memo
  });
  const unitPrice = normalizeOpenAIUnitPrice({
    memo,
    rawUnitPrice,
    analysisContext,
    assetClass
  });
  const marketValue = normalizeOpenAIMarketValue({
    memo,
    rawMarketValue,
    quantity,
    rawUnitPrice,
    unitPrice,
    analysisContext,
    assetClass
  });

  if (marketValue == null || marketValue <= 0) {
    return null;
  }

  return {
    id: randomUUID(),
    name,
    symbol,
    institution,
    assetClass,
    quantity,
    unitPrice,
    marketValue,
    currency,
    country,
    memo: memo.length > 0 ? `OpenAI 분석: ${memo}` : "OpenAI 이미지 분석"
  };
}

function normalizeHoldingAssetClass(assetClass, { rawName, symbol, memo, currency, analysisContext }) {
  if (assetClass !== "cashEquivalent") {
    return assetClass;
  }

  const combinedText = `${rawName} ${symbol} ${memo}`.trim();
  if (looksLikeSpecificStockHolding({ rawName, symbol, memo, analysisContext })) {
    return currency === "KRW" ? "domesticStock" : "foreignStock";
  }

  if (analysisContext.isMeritzSuper365Screen && /추정예수금|출금가능금액|주문가능금액\(현금\)|D2예수금/i.test(combinedText)) {
    return "cashEquivalent";
  }

  return assetClass;
}

function shouldDiscardOpenAIHolding({ rawName, normalizedName, symbol, memo, assetClass, analysisContext }) {
  const combinedText = `${rawName} ${normalizedName} ${symbol} ${memo}`.trim();

  if (assetClass === "cashEquivalent") {
    if (looksLikeStockSummaryText(combinedText)) {
      return true;
    }

    if (looksLikeStockSettlementLabel(combinedText)) {
      return true;
    }

    if (analysisContext.isWooriInvestmentScreen && /내\s*주식|종목명|평가금|현재가/i.test(combinedText)) {
      return true;
    }
  }

  return false;
}

function looksLikeSpecificStockHolding({ rawName, symbol, memo, analysisContext }) {
  const combinedText = `${rawName} ${symbol} ${memo}`.trim();

  if (/예수금|증거금|주문가능|출금가능|원화예수금|외화예수금|D2예수금|추정예수금|환전/i.test(combinedText)) {
    return false;
  }

  if (looksLikeStockSettlementLabel(combinedText) && looksLikeHoldingName(rawName, symbol)) {
    return true;
  }

  if (analysisContext.isMeritzSuper365Screen && looksLikeHoldingName(rawName, symbol) && /보유수량|매입가|매입금액|수익률|평가손익|현재가|현금/i.test(combinedText)) {
    return true;
  }

  return false;
}

function looksLikeHoldingName(rawName, symbol) {
  const name = cleanupAssetName(String(rawName ?? "").trim());
  if (name.length === 0) {
    return false;
  }

  if (/현금|예수금|잔고|주문가능|증거금|내 주식|주식평가금액|평가금액|순평가/i.test(name)) {
    return false;
  }

  if (symbol.length > 0) {
    return true;
  }

  return /[A-Za-z가-힣]/.test(name);
}

function looksLikeStockSummaryText(text) {
  return /내\s*주식|주식평가금액|평가금액\(A\)|순평가\(A-B\)|실현손익|평가손익|종목명\s*순/i.test(text);
}

function looksLikeStockSettlementLabel(text) {
  return /현금\s*[•|]\s*(?:[0-9]+주|[A-Z]{2,10})/i.test(text);
}

function buildOpenAIAnalysisContext({ institutions, previewLines }) {
  const previewText = previewLines.join("\n");
  const previewInstitution = inferInstitution(previewText);
  const normalizedInstitutions = Array.from(new Set(
    [...institutions, previewInstitution]
      .map((value) => normalizeInstitutionName(value))
      .filter((value) => value.length > 0)
  ));
  const securitiesInstitutions = normalizedInstitutions.filter(isSecuritiesInstitution);
  const primaryInstitution = previewInstitution.length > 0
    ? previewInstitution
    : (securitiesInstitutions.length === 1 ? securitiesInstitutions[0] : "");

  return {
    previewText,
    institutions: normalizedInstitutions,
    primaryInstitution,
    isKiwoomOverseasScreen: /해외잔고|위탁종합|키움전체|영웅문/i.test(previewText),
    isMeritzSuper365Screen: /Super365/i.test(previewText),
    isWooriInvestmentScreen: looksLikeWooriInvestmentScreen(previewText),
    hasDerivedAppSignals: /(대시보드|업로드|히스토리|설정|dashboard|upload|history|settings)/i.test(previewText)
  };
}

function reconcileInstitutionHints(institutions, analysisContext) {
  if (analysisContext.isKiwoomOverseasScreen && analysisContext.primaryInstitution === "키움증권") {
    institutions.delete("KB증권");
  }

  if (analysisContext.isMeritzSuper365Screen && analysisContext.primaryInstitution === "메리츠증권") {
    institutions.delete("KB증권");
  }

  if (analysisContext.isWooriInvestmentScreen && analysisContext.primaryInstitution === "우리투자증권") {
    institutions.delete("KB증권");
  }
}

function normalizeInstitutionName(value) {
  const trimmed = String(value ?? "").trim();
  if (trimmed.length === 0) {
    return "";
  }

  if (/업비트|upbit/i.test(trimmed)) {
    return "Upbit";
  }
  if (/^okx$/i.test(trimmed) || /okx/i.test(trimmed)) {
    return "OKX";
  }
  if (/키움|영웅문/i.test(trimmed)) {
    return "키움증권";
  }
  if (/kb/i.test(trimmed) || /kb증권/i.test(trimmed)) {
    return "KB증권";
  }
  if (/메리츠/i.test(trimmed)) {
    return "메리츠증권";
  }
  if (/super365/i.test(trimmed)) {
    return "메리츠증권";
  }
  if (/우리투자|woori/i.test(trimmed)) {
    return "우리투자증권";
  }
  if (/신한/i.test(trimmed)) {
    return "신한은행";
  }
  if (/토스/i.test(trimmed)) {
    return "토스";
  }

  return trimmed;
}

function isSecuritiesInstitution(value) {
  return /증권/.test(value);
}

function normalizeOpenAIInstitution(rawInstitution, { analysisContext, assetClass, currency, symbol, memo }) {
  const normalized = normalizeInstitutionName(rawInstitution);
  const combinedText = `${normalized} ${symbol} ${memo}`.trim();

  if (analysisContext.isKiwoomOverseasScreen && assetClass === "foreignStock") {
    if (normalized.length === 0 || normalized === "KB증권" || /키움전체|위탁종합|해외잔고/i.test(combinedText)) {
      return "키움증권";
    }
  }

  if (normalized.length > 0) {
    if (analysisContext.isMeritzSuper365Screen && /KB증권|키움증권|미래에셋증권/.test(normalized)) {
      return "메리츠증권";
    }
    if (analysisContext.isWooriInvestmentScreen && /KB증권|키움증권|미래에셋증권|메리츠증권/.test(normalized)) {
      return "우리투자증권";
    }
    return normalized;
  }

  if (analysisContext.primaryInstitution.length > 0 && (assetClass === "foreignStock" || assetClass === "domesticStock" || assetClass === "cashEquivalent")) {
    return analysisContext.primaryInstitution;
  }

  if (analysisContext.isMeritzSuper365Screen && (assetClass === "foreignStock" || assetClass === "domesticStock" || assetClass === "cashEquivalent")) {
    return "메리츠증권";
  }

  if (analysisContext.isWooriInvestmentScreen && (assetClass === "foreignStock" || assetClass === "domesticStock" || assetClass === "cashEquivalent")) {
    return "우리투자증권";
  }

  if ((assetClass === "crypto" || currency === "USDT") && /OKX/i.test(analysisContext.previewText)) {
    return "OKX";
  }

  if ((assetClass === "crypto" || symbol === "BTC" || symbol === "ETH") && /업비트|Upbit/i.test(analysisContext.previewText)) {
    return "Upbit";
  }

  return normalized;
}

function normalizeOpenAIUnitPrice({ memo, rawUnitPrice, analysisContext, assetClass }) {
  if (analysisContext.isKiwoomOverseasScreen && assetClass === "foreignStock") {
    const explicitAveragePrice = extractLabeledNumber(memo, ["평균단가", "현재가", "단가"]);
    if (explicitAveragePrice != null && explicitAveragePrice > 0) {
      return explicitAveragePrice;
    }

    return null;
  }

  return rawUnitPrice;
}

function normalizeOpenAIMarketValue({ memo, rawMarketValue, quantity, rawUnitPrice, unitPrice, analysisContext, assetClass }) {
  if (analysisContext.isKiwoomOverseasScreen && assetClass === "foreignStock") {
    const explicitEvaluationAmount = extractLabeledNumber(memo, ["평가금액", "평가 금액", "evaluation", "market value"]);
    if (explicitEvaluationAmount != null && explicitEvaluationAmount > 0) {
      return explicitEvaluationAmount;
    }

    const numericTokens = extractNumericTokens(memo).map((token) => token.value).filter((value) => value > 0);
    if (numericTokens.length >= 3) {
      return numericTokens[numericTokens.length - 1];
    }

    const comparableUnitPrice = rawUnitPrice ?? unitPrice;
    if (quantity != null && comparableUnitPrice != null && rawMarketValue != null && isApproximatelyEqual(rawMarketValue, quantity * comparableUnitPrice)) {
      return rawMarketValue / quantity;
    }
  }

  return rawMarketValue;
}

function extractLabeledNumber(text, labels) {
  const source = String(text ?? "");
  for (const label of labels) {
    const pattern = new RegExp(`${escapeRegExp(label)}\\s*[:=]?\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)`, "i");
    const match = source.match(pattern);
    if (match) {
      const value = parseNumber(match[1]);
      if (Number.isFinite(value) && value > 0) {
        return value;
      }
    }
  }

  return null;
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function isApproximatelyEqual(left, right) {
  if (Number.isFinite(left) === false || Number.isFinite(right) === false) {
    return false;
  }

  const tolerance = Math.max(0.01, Math.abs(right) * 0.001);
  return Math.abs(left - right) <= tolerance;
}

function looksLikeWooriInvestmentScreen(text) {
  const normalized = String(text ?? "");
  return /투자\s+연금\/ISA\s+CMA\s+예적금/i.test(normalized)
    || (/연금\/ISA/i.test(normalized) && /CMA/i.test(normalized) && /예적금/i.test(normalized) && /국내현재가|국내주문|국내잔고/i.test(normalized));
}

function normalizeAssetClass(value, fallbackValue = "unknown") {
  const normalized = String(value ?? "").trim().toLowerCase();

  if (normalized === "domesticstock" || normalized === "domestic_stock" || normalized === "국내주식") {
    return "domesticStock";
  }

  if (normalized === "foreignstock" || normalized === "foreign_stock" || normalized === "해외주식") {
    return "foreignStock";
  }

  if (normalized === "cashequivalent" || normalized === "cash_equivalent" || normalized === "현금성자산") {
    return "cashEquivalent";
  }

  if (normalized === "crypto" || normalized === "코인") {
    return "crypto";
  }

  if (normalized === "bond" || normalized === "채권") {
    return "bond";
  }

  if (normalized === "unknown" || normalized.length === 0) {
    return fallbackValue;
  }

  return fallbackValue;
}

function normalizeCountry(value, assetClass, currency) {
  const trimmed = String(value ?? "").trim().toUpperCase();
  if (trimmed.length > 0) {
    return trimmed;
  }

  return inferCountry(assetClass, currency);
}

function normalizeCurrency(value) {
  const normalized = detectCurrencyFromText(value);
  if (normalized.length > 0) {
    return normalized;
  }

  return "KRW";
}

function normalizeHoldingCurrency({ rawCurrency, rawName, memo, symbol }) {
  const direct = normalizeCurrency(rawCurrency);
  if (direct !== "KRW" || /\bKRW\b|원화/i.test(String(rawCurrency ?? ""))) {
    return direct;
  }

  const inferred = detectCurrencyFromText(`${rawName} ${memo} ${symbol}`.trim());
  if (inferred.length > 0) {
    return inferred;
  }

  return direct;
}

function detectCurrencyFromText(value) {
  const text = String(value ?? "").trim();
  if (text.length === 0) {
    return "";
  }

  if (/스위스\s*프랑|Swiss\s*Franc|\bCHF\b/i.test(text)) {
    return "CHF";
  }
  if (/미국\s*달러|US\s*Dollar|\bUSD\b|\$/i.test(text)) {
    return "USD";
  }
  if (/원화|\bKRW\b|₩/i.test(text)) {
    return "KRW";
  }
  if (/유로|\bEUR\b/i.test(text)) {
    return "EUR";
  }
  if (/엔화|일본엔|\bJPY\b/i.test(text)) {
    return "JPY";
  }
  if (/홍콩달러|\bHKD\b/i.test(text)) {
    return "HKD";
  }
  if (/위안|인민폐|\bCNY\b/i.test(text)) {
    return "CNY";
  }
  if (/파운드|\bGBP\b/i.test(text)) {
    return "GBP";
  }
  if (/\bUSDT\b/i.test(text)) {
    return "USDT";
  }
  if (/\bUSDC\b/i.test(text)) {
    return "USDC";
  }

  return "";
}

function normalizeHoldingName({ rawName, assetClass, currency, memo, symbol }) {
  if (assetClass !== "cashEquivalent") {
    return rawName;
  }

  const source = `${rawName} ${memo}`.trim();
  if (/D2예수금/i.test(source)) {
    return "D2예수금";
  }
  if (/원화\s*예수금|원화예수금/i.test(source) || currency === "KRW") {
    return "원화예수금";
  }
  if (stablecoinSymbols.has(symbol)) {
    return symbol;
  }
  if (/외화추정예수금|외화예수금|외화잔고|예수금/i.test(source) || currency !== "KRW") {
    return `${currencyDisplayName(currency)} 예수금`;
  }

  return rawName;
}

function currencyDisplayName(currency) {
  switch (currency) {
    case "USD":
      return "미국달러";
    case "CHF":
      return "스위스프랑";
    case "EUR":
      return "유로";
    case "JPY":
      return "엔화";
    case "HKD":
      return "홍콩달러";
    case "CNY":
      return "위안화";
    case "GBP":
      return "영국파운드";
    case "KRW":
      return "원화";
    default:
      return currency;
  }
}

function normalizePreviewLines(previewLines) {
  return (Array.isArray(previewLines) ? previewLines : [])
    .map((line) => normalizeLine(line))
    .filter((line) => line.length > 0)
    .slice(0, 8);
}

function normalizeCount(recognizedLineCount, previewLines) {
  const numeric = Number(recognizedLineCount);
  if (Number.isInteger(numeric) && numeric >= 0) {
    return numeric;
  }

  return normalizePreviewLines(previewLines).length;
}

function toNullableFiniteNumber(value) {
  if (value == null || value === "") {
    return null;
  }

  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : null;
}

function normalizeMimeType(value, filePath) {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (normalized.startsWith("image/")) {
    return normalized;
  }

  const extension = path.extname(filePath).toLowerCase();
  if (extension === ".png") {
    return "image/png";
  }
  if (extension === ".webp") {
    return "image/webp";
  }
  if (extension === ".gif") {
    return "image/gif";
  }
  return "image/jpeg";
}

function supportsReasoning(model) {
  return /^(gpt-5|o[1-9]|o[1-9]-)/i.test(model);
}

function resolveAnalysisProvider(requestedProvider) {
  if (requestedProvider === "openai" || requestedProvider === "vision") {
    return requestedProvider;
  }

  if (openAIAPIKey.length > 0) {
    return "openai";
  }

  if (process.platform === "darwin") {
    return "vision";
  }

  return "openai";
}

function analyzeOCRResults(ocrResults) {
  const allHoldings = [];
  const fallbackTotals = [];
  const explicitRates = new Map([["KRW", 1]]);
  const institutionSet = new Set();
  let recognizedLineCount = 0;

  for (const result of ocrResults) {
    const lines = Array.isArray(result.lines)
      ? result.lines
          .map((line) => normalizeLine(line.text ?? ""))
          .filter((line) => line.length > 0)
      : [];

    recognizedLineCount += lines.length;
    const context = inferImageContext(lines);

    if (context.institution.length > 0) {
      institutionSet.add(context.institution);
    }

    for (const [currency, rate] of extractExplicitRates(lines)) {
      explicitRates.set(currency, rate);
    }

    const parsed = parseHoldingsFromLines(lines, context);
    allHoldings.push(...parsed.holdings);
    fallbackTotals.push(...parsed.fallbackTotals);
  }

  let holdings = dedupeHoldings(allHoldings);

  if (holdings.length === 0 && fallbackTotals.length > 0) {
    holdings = fallbackTotals
      .sort((left, right) => right.marketValue - left.marketValue)
      .slice(0, 1)
      .map((candidate) => ({
        id: randomUUID(),
        name: "OCR 추정 총자산",
        symbol: "",
        institution: candidate.institution,
        assetClass: "unknown",
        quantity: null,
        unitPrice: null,
        marketValue: candidate.marketValue,
        currency: candidate.currency,
        country: "",
        memo: `요약 라인 기반 추정: ${candidate.sourceLine}`
      }));
  }

  const institutions = Array.from(institutionSet).sort();

  return {
    holdings,
    explicitRates,
    institutions,
    recognizedLineCount,
    previewLines: ocrResults
      .flatMap((result) => (Array.isArray(result.lines) ? result.lines : []))
      .map((line) => normalizeLine(line.text ?? ""))
      .filter((line) => line.length > 0)
      .slice(0, 8)
  };
}

function inferImageContext(lines) {
  const joinedText = lines.join("\n");
  const upperText = joinedText.toUpperCase();

  return {
    institution: inferInstitution(joinedText),
    defaultAssetClass: inferDefaultAssetClass(joinedText, upperText),
    defaultCurrency: inferDefaultCurrency(joinedText, upperText)
  };
}

function inferInstitution(text) {
  if (/업비트/i.test(text)) {
    return "Upbit";
  }
  if (/OKX/i.test(text)) {
    return "OKX";
  }
  if (/키움|영웅문/i.test(text)) {
    return "키움증권";
  }
  if (looksLikeWooriInvestmentScreen(text)) {
    return "우리투자증권";
  }
  if (/메리츠/i.test(text)) {
    return "메리츠증권";
  }
  if (/Super365/i.test(text)) {
    return "메리츠증권";
  }
  if (/신한/i.test(text)) {
    return "신한은행";
  }
  if (/토스/i.test(text)) {
    return "토스";
  }

  return "";
}

function inferDefaultAssetClass(text, upperText) {
  for (const keyword of imageTypeSignals.bond) {
    if (text.includes(keyword) || upperText.includes(keyword)) {
      return "bond";
    }
  }

  for (const keyword of imageTypeSignals.crypto) {
    if (text.includes(keyword) || upperText.includes(keyword)) {
      return "crypto";
    }
  }

  for (const keyword of imageTypeSignals.foreignStock) {
    if (text.includes(keyword) || upperText.includes(keyword)) {
      return "foreignStock";
    }
  }

  for (const keyword of imageTypeSignals.domesticStock) {
    if (text.includes(keyword) || upperText.includes(keyword)) {
      return "domesticStock";
    }
  }

  for (const keyword of imageTypeSignals.cashEquivalent) {
    if (text.includes(keyword) || upperText.includes(keyword)) {
      return "cashEquivalent";
    }
  }

  return "unknown";
}

function inferDefaultCurrency(text, upperText) {
  if (upperText.includes("USDT")) {
    return "USDT";
  }
  if (upperText.includes("CHF") || /스위스\s*프랑/i.test(text)) {
    return "CHF";
  }
  if (upperText.includes("USD") || text.includes("$")) {
    return "USD";
  }
  return "KRW";
}

function extractExplicitRates(lines) {
  const results = [];

  for (const line of lines) {
    const usdSlashKRW = line.match(/USD\s*\/\s*KRW\s*([0-9][0-9,]*(?:\.[0-9]+)?)/i);
    if (usdSlashKRW) {
      results.push(["USD", parseNumber(usdSlashKRW[1])]);
      continue;
    }

    const usdEquation = line.match(/1\s*USD[^0-9]*([0-9][0-9,]*(?:\.[0-9]+)?)/i);
    if (usdEquation) {
      results.push(["USD", parseNumber(usdEquation[1])]);
      continue;
    }

    const usdtEquation = line.match(/1\s*USDT[^0-9]*([0-9][0-9,]*(?:\.[0-9]+)?)/i);
    if (usdtEquation) {
      results.push(["USDT", parseNumber(usdtEquation[1])]);
    }
  }

  return results.filter(([, rate]) => Number.isFinite(rate) && rate > 0);
}

function parseHoldingsFromLines(lines, context) {
  const holdings = [];
  const fallbackTotals = [];
  let pendingName = "";

  for (let index = 0; index < lines.length; index += 1) {
    let line = lines[index];
    if (isNoiseLine(line)) {
      continue;
    }

    const nextLine = lines[index + 1];
    if (nextLine && shouldMergeWithNextLine(line, nextLine)) {
      line = `${line} ${nextLine}`;
      index += 1
    }

    const isCashLikeLine = /예수금|잔고|현금|출금가능|CASH|CMA|MMF|외화자산/i.test(line);
    if (isCashLikeLine && hasMeaningfulNumber(line)) {
      const cashHolding = parseHoldingLine(line, {
        ...context,
        defaultAssetClass: "cashEquivalent",
        defaultCurrency: inferCurrency(line, context.defaultCurrency)
      }, pendingName);

      if (cashHolding) {
        holdings.push(cashHolding);
        pendingName = "";
        continue;
      }
    }

    if (containsSummaryLine(line)) {
      const fallbackTotal = parseSummaryLine(line, context);
      if (fallbackTotal) {
        fallbackTotals.push(fallbackTotal);
      }
      continue;
    }

    if (hasMeaningfulNumber(line) === false) {
      if (looksLikeAssetName(line) && line !== context.institution) {
        pendingName = line;
      }
      continue;
    }

    const parsed = parseHoldingLine(line, context, pendingName);
    if (parsed) {
      holdings.push(parsed);
      pendingName = "";
      continue;
    }

    if (looksLikeAssetName(line)) {
      pendingName = line;
    }
  }

  return { holdings, fallbackTotals };
}

function parseHoldingLine(line, context, pendingName) {
  const symbol = extractSymbol(line);
  const currency = inferCurrency(line, context.defaultCurrency);
  const assetClass = inferAssetClass(line, context.defaultAssetClass, currency, symbol);
  const quantity = extractQuantity(line);
  const marketValue = extractMarketValue(line, symbol);
  const rawName = extractName(line, symbol, pendingName);

  if (rawName.length === 0 || marketValue == null || marketValue <= 0) {
    return null;
  }

  if (isHeaderLikeName(rawName)) {
    return null;
  }

  return {
    id: randomUUID(),
    name: rawName,
    symbol,
    institution: context.institution,
    assetClass,
    quantity,
    unitPrice: null,
    marketValue,
    currency,
    country: inferCountry(assetClass, currency),
    memo: `OCR 라인: ${line}`
  };
}

function extractQuantity(line) {
  const explicitQuantity = line.match(/([0-9][0-9,]*(?:\.[0-9]+)?)\s*(주|개|EA)/i);
  if (explicitQuantity) {
    const value = parseNumber(explicitQuantity[1]);
    return Number.isFinite(value) ? value : null;
  }

  const numericTokens = extractNumericTokens(line)
    .filter((token) => /^\d{6}$/.test(token.raw) === false)
    .map((token) => token.value)
    .filter((value) => value > 0 && value < 100_000);

  if (numericTokens.length >= 2) {
    return numericTokens[0];
  }

  return null;
}

function extractMarketValue(line, symbol) {
  const numericTokens = extractNumericTokens(line)
    .filter((token) => token.raw !== symbol)
    .map((token) => token.value)
    .filter((value) => value > 0);

  if (numericTokens.length === 0) {
    return null;
  }

  if (/[₩원]/.test(line) || /\bKRW\b/i.test(line) || /\$/.test(line) || /\bUSD\b/i.test(line) || /\bUSDT\b/i.test(line)) {
    return numericTokens[numericTokens.length - 1];
  }

  return Math.max(...numericTokens);
}

function extractName(line, symbol, pendingName) {
  let normalized = line;

  if (symbol.length > 0) {
    normalized = normalized.replace(symbol, " ");
  }

  normalized = normalized
    .replace(/\b(?:USD|KRW|USDT|USDC|원|달러|수량|평가금액|보유수량|현재가|매입가|손익|수익률|주|개|EA)\b/giu, " ")
    .replace(/[$₩]/g, " ")
    .replace(/[0-9][0-9,]*(?:\.[0-9]+)?/g, " ")
    .replace(/[()[\]{}|]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (normalized.length === 0 && pendingName.length > 0) {
    const pendingCleaned = cleanupAssetName(pendingName);
    if (isHeaderLikeName(pendingCleaned) === false && pendingCleaned.length > 0) {
      return pendingCleaned;
    }
  }

  const cleaned = cleanupAssetName(normalized);
  const stablecoinBalance = line.match(/^\s*(USDT|USDC)\s*잔고/i);
  if (stablecoinBalance) {
    return `${stablecoinBalance[1].toUpperCase()} 잔고`;
  }

  if (cleaned.length > 0) {
    return cleaned;
  }

  if (symbol.length > 0) {
    return symbol;
  }

  return cleaned;
}

function cleanupAssetName(name) {
  return name
    .replace(/\b(?:총자산|총평가|합계|평가손익|잔고내역|보유자산)\b/giu, " ")
    .replace(/(^|\s)(주|원)(?=\s|$)/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function extractSymbol(line) {
  const domesticCode = line.match(/\b\d{6}\b/);
  if (domesticCode) {
    return domesticCode[0];
  }

  const symbolCandidates = line.match(/\b[A-Z]{2,10}\b/g) ?? [];
  for (const token of symbolCandidates) {
    if (excludedSymbolTokens.has(token)) {
      continue;
    }
    return token;
  }

  return "";
}

function inferCurrency(line, defaultCurrency) {
  if (/원|KRW/i.test(line)) {
    return "KRW";
  }
  if (/\bUSDT\b/i.test(line)) {
    return "USDT";
  }
  if (/\bUSD\b/i.test(line) || /\$/.test(line) || /달러/.test(line)) {
    return "USD";
  }
  return defaultCurrency || "KRW";
}

function inferAssetClass(line, defaultAssetClass, currency, symbol) {
  const upperLine = line.toUpperCase();

  if (/채권|국채|회사채|BOND|TREASURY/i.test(line)) {
    return "bond";
  }

  if (/예수금|잔고|현금|출금가능|예금|CASH|CMA|MMF/i.test(line)) {
    return "cashEquivalent";
  }

  if (stablecoinSymbols.has(symbol) || /^\s*(USDT|USDC)\b/i.test(line)) {
    return "cashEquivalent";
  }

  if (cryptoSymbols.has(symbol) || /비트코인|이더리움|코인|가상자산/i.test(line)) {
    return "crypto";
  }

  if ((/^[0-9]{6}$/.test(symbol) || /[가-힣]/.test(line)) && currency === "KRW") {
    return "domesticStock";
  }

  if (defaultAssetClass === "foreignStock" || /NASDAQ|NYSE|미국/i.test(line)) {
    return "foreignStock";
  }

  if (defaultAssetClass === "domesticStock") {
    return "domesticStock";
  }

  if (currency !== "KRW" && /[A-Z]{2,10}/.test(upperLine)) {
    return "foreignStock";
  }

  if (/[가-힣]/.test(line)) {
    return "domesticStock";
  }

  return defaultAssetClass || "unknown";
}

function inferCountry(assetClass, currency) {
  if (assetClass === "domesticStock" || currency === "KRW") {
    return "KR";
  }
  if (assetClass === "foreignStock") {
    return "US";
  }
  if (assetClass === "cashEquivalent") {
    if (currency === "USD") {
      return "US";
    }
    if (currency === "CHF") {
      return "CH";
    }
    if (currency === "JPY") {
      return "JP";
    }
    if (currency === "EUR") {
      return "EU";
    }
    if (currency === "HKD") {
      return "HK";
    }
    if (currency === "CNY") {
      return "CN";
    }
    if (currency === "GBP") {
      return "GB";
    }
  }
  if (assetClass === "crypto" || currency === "USDT") {
    return "SC";
  }
  return "";
}

function dedupeHoldings(holdings) {
  const deduped = new Map();

  for (const holding of holdings) {
    const key = [
      holding.name.toLowerCase(),
      holding.symbol.toLowerCase(),
      holding.assetClass,
      holding.currency,
      holding.institution.toLowerCase()
    ].join("|");

    const existing = deduped.get(key);
    if (existing == null) {
      deduped.set(key, holding);
      continue;
    }

    if ((holding.marketValue ?? 0) > (existing.marketValue ?? 0)) {
      deduped.set(key, holding);
    }
  }

  return Array.from(deduped.values()).sort((left, right) => {
    return (right.marketValue ?? 0) - (left.marketValue ?? 0);
  });
}

function parseSummaryLine(line, context) {
  const numericTokens = extractNumericTokens(line).map((token) => token.value).filter((value) => value > 0);
  if (numericTokens.length === 0) {
    return null;
  }

  return {
    marketValue: Math.max(...numericTokens),
    currency: inferCurrency(line, context.defaultCurrency),
    institution: context.institution,
    sourceLine: line
  };
}

async function buildExchangeRates({ capturedAt, explicitRates, currencies }) {
  const normalizedCurrencies = Array.from(currencies)
    .map((currency) => currency.toUpperCase())
    .filter((currency) => currency.length > 0);

  const rates = [
    {
      id: randomUUID(),
      baseCurrency: "KRW",
      quoteCurrency: "KRW",
      rateToQuote: 1,
      source: "system",
      observedAt: capturedAt
    }
  ];

  const liveRates = await fetchLiveKRWRates(normalizedCurrencies);

  for (const currency of normalizedCurrencies) {
    if (currency === "KRW") {
      continue;
    }

    let rate = explicitRates.get(currency);
    let source = "ocr";

    if (rate == null) {
      rate = liveRates.get(currency);
      source = "live-open-er-api";
    }

    if (rate == null && currency === "USDT") {
      rate = explicitRates.get("USD") ?? liveRates.get("USD") ?? fallbackKRWRates.USDT;
      source = rate === fallbackKRWRates.USDT ? "fallback-default" : "usd-proxy";
    }

    if (rate == null) {
      rate = fallbackKRWRates[currency];
      source = "fallback-default";
    }

    if (rate == null) {
      continue;
    }

    rates.push({
      id: randomUUID(),
      baseCurrency: currency,
      quoteCurrency: "KRW",
      rateToQuote: rate,
      source,
      observedAt: new Date().toISOString()
    });
  }

  return rates;
}

async function fetchLiveKRWRates(currencies) {
  const liveRates = new Map();
  const uniqueCurrencies = Array.from(new Set(currencies.filter((currency) => currency !== "KRW" && currency !== "USDT")));

  await Promise.all(
    uniqueCurrencies.map(async (currency) => {
      try {
        const response = await fetch(`https://open.er-api.com/v6/latest/${currency}`, {
          signal: AbortSignal.timeout(4000)
        });

        if (response.ok === false) {
          return;
        }

        const payload = await response.json();
        const rate = payload?.rates?.KRW;
        if (Number.isFinite(rate) && rate > 0) {
          liveRates.set(currency, rate);
        }
      } catch {
        // 네트워크 실패 시 기본값으로 넘어간다.
      }
    })
  );

  if (currencies.includes("USDT") && liveRates.has("USD")) {
    liveRates.set("USDT", liveRates.get("USD"));
  }

  return liveRates;
}

function buildAnalysisNote({ imageCount, analysis, exchangeRates, provider }) {
  const noteLines = [
    `${imageCount}장 스크린샷 분석 결과`,
    `분석 엔진: ${provider === "openai" ? `OpenAI ${openAIModel}` : "Apple Vision OCR"}`,
    `인식/요약 줄 수: ${analysis.recognizedLineCount}`,
    `파싱된 자산 수: ${analysis.holdings.length}`
  ];

  if (analysis.institutions.length > 0) {
    noteLines.push(`추정 기관: ${analysis.institutions.join(", ")}`);
  }

  const nonKRWRates = exchangeRates
    .filter((rate) => rate.baseCurrency !== "KRW")
    .map((rate) => `${rate.baseCurrency}/KRW ${rate.rateToQuote} (${rate.source})`);

  if (nonKRWRates.length > 0) {
    noteLines.push(`적용 환율: ${nonKRWRates.join(", ")}`);
  }

  if (analysis.previewLines.length > 0) {
    noteLines.push(`OCR 미리보기: ${analysis.previewLines.join(" | ")}`);
  }

  if (analysis.holdings.length === 0) {
    noteLines.push("정확히 파싱된 자산이 없어 검토가 필요합니다.");
  }

  return noteLines.join("\n");
}

function normalizeLine(line) {
  return String(line)
    .replace(/(\d)\s*,\s*(\d)/g, "$1,$2")
    .replace(/\$\s+/g, "$")
    .replace(/\s+/g, " ")
    .replace(/[|]/g, " ")
    .trim();
}

function isNoiseLine(line) {
  return (
    line.length < 2 ||
    /^([0-9]{1,2}:[0-9]{2}|LTE|KT|SKT|5G|Wi-?Fi|배터리)$/i.test(line) ||
    /^(뒤로|검색|메뉴|설정|닫기|홈)$/i.test(line) ||
    /snapshot/i.test(line) ||
    /myport ocr sample image/i.test(line) ||
    /^보유 자산$/i.test(line) ||
    /^trading account$/i.test(line) ||
    /통합 조회/i.test(line)
  );
}

function shouldMergeWithNextLine(currentLine, nextLine) {
  if (nextLine == null) {
    return false;
  }

  const hasLetters = /[A-Za-z가-힣]/.test(currentLine);
  const nextLooksNumeric = /^[0-9,.\s]+(?:USD|USDT|KRW|원|달러)?$/i.test(nextLine);
  const currentHasAmount = extractNumericTokens(currentLine).some((token) => token.value >= 1_000);

  return hasLetters && nextLooksNumeric && currentHasAmount === false;
}

function looksLikeAssetName(line) {
  return (
    hasMeaningfulNumber(line) === false &&
    line.length >= 2 &&
    line.length <= 24 &&
    /[A-Za-z가-힣]/.test(line) &&
    isHeaderLikeName(line) === false
  );
}

function isHeaderLikeName(line) {
  return /종목명|평가금액|보유수량|현재가|수익률|손익|합계|총자산|잔고내역|보유자산|assets|잔고|자산/i.test(line);
}

function containsSummaryLine(line) {
  return /총자산|총 평가|총평가|합계|총액|자산합계|순자산/i.test(line);
}

function hasMeaningfulNumber(line) {
  return extractNumericTokens(line).some((token) => token.value > 0);
}

function extractNumericTokens(line) {
  return Array.from(line.matchAll(/\d[\d,]*(?:\.\d+)?/g))
    .map((match) => ({
      raw: match[0],
      value: parseNumber(match[0])
    }))
    .filter((token) => Number.isFinite(token.value));
}

function parseNumber(value) {
  return Number.parseFloat(String(value).replaceAll(",", ""));
}
