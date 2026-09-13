/*
 * RecipeClipper portable backup format.
 *
 * The native app currently writes backup.json inside a store-only ZIP.  The
 * web app deliberately keeps that field vocabulary instead of inventing a
 * second recipe model.  `format` and `schemaVersion` are additive metadata;
 * `formatVersion` remains for compatibility with existing iOS backups.
 */

export const PORTABLE_FORMAT = "recipeclipper";
export const PORTABLE_SCHEMA_VERSION = 1;
export const NATIVE_FORMAT_VERSION = 2;

const ROOT_FIELDS = new Set([
  "format",
  "schemaVersion",
  "formatVersion",
  "exportedAt",
  "recipes",
]);

const RECIPE_FIELDS = new Set([
  "id",
  "title",
  "summary",
  "sourceURL",
  "sourceHost",
  "sourceImageURL",
  "imagePath",
  "notes",
  "tags",
  "servings",
  "ingredients",
  "instructions",
  "checkedIngredients",
  "normalizedSourceURL",
  "sourceKind",
  "isFavorite",
  "rating",
  "wantsRemake",
  "extractedRawText",
  "rawImportedText",
  "rawImportedHTML",
  "importedTextSource",
  "extractionConfidence",
  "extractionWarnings",
  "ingredientSource",
  "instructionSource",
  "createdAt",
  "updatedAt",
  "cookLogs",
]);

const COOK_LOG_FIELDS = new Set([
  "id",
  "cookedAt",
  "memo",
  "imagePath",
  "rating",
  "improvementMemo",
  "arrangementMemo",
]);

export class BackupValidationError extends Error {
  constructor(message, details = []) {
    super(message);
    this.name = "BackupValidationError";
    this.details = details;
  }
}

export function newUUID() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  const bytes = new Uint8Array(16);
  globalThis.crypto?.getRandomValues?.(bytes);
  if (!bytes.some(Boolean)) {
    for (let index = 0; index < bytes.length; index += 1) {
      bytes[index] = Math.floor(Math.random() * 256);
    }
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function asString(value, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

export function asOptionalString(value) {
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function asBoolean(value, fallback = false) {
  return typeof value === "boolean" ? value : fallback;
}

export function asNumber(value, fallback = 0) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

export function asInteger(value, fallback = 0) {
  return Number.isInteger(value) ? value : fallback;
}

export function normalizeLines(value) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((line) => typeof line === "string")
    .map((line) => line.trim())
    .filter(Boolean);
}

export function normalizeTags(value) {
  const source = Array.isArray(value) ? value : String(value ?? "").split(/[\n,]/);
  const seen = new Set();
  return source
    .filter((tag) => typeof tag === "string")
    .map((tag) => tag.trim().replace(/^#/, ""))
    .filter(Boolean)
    .filter((tag) => {
      const key = tag.toLocaleLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

export function dateIsValid(value) {
  return typeof value === "string" && value.trim() !== "" && !Number.isNaN(Date.parse(value));
}

function sourceKindFor(sourceURL, sourceHost, requested) {
  if (requested) return requested;
  const source = `${sourceHost ?? ""} ${sourceURL ?? ""}`.toLocaleLowerCase();
  if (source.includes("instagram.com")) return "instagram";
  if (source.includes("cookpad.com")) return "cookpad";
  if (source.includes("youtube.com") || source.includes("youtu.be")) return "youtube";
  if (!source.trim()) return "original";
  return "web";
}

function unknownFields(raw, fields) {
  return Object.fromEntries(
    Object.entries(raw).filter(([key]) => !fields.has(key)),
  );
}

function normalizeCookLog(raw, index, issues) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    issues.push(`cookLogs[${index}] is not an object`);
    return null;
  }

  if (typeof raw.id !== "string" || raw.id.trim() === "") {
    issues.push(`cookLogs[${index}] is missing id`);
  }
  if (raw.cookedAt !== undefined && !dateIsValid(raw.cookedAt)) {
    issues.push(`cookLogs[${index}].cookedAt is not a valid ISO date`);
  }

  return {
    id: asString(raw.id, newUUID()),
    cookedAt: asString(raw.cookedAt, new Date(0).toISOString()),
    memo: asString(raw.memo),
    imagePath: asOptionalString(raw.imagePath),
    rating: Math.max(0, Math.min(5, asInteger(raw.rating))),
    improvementMemo: asString(raw.improvementMemo),
    arrangementMemo: asString(raw.arrangementMemo),
    _unknownFields: unknownFields(raw, COOK_LOG_FIELDS),
    _providedFields: new Set(Object.keys(raw)),
  };
}

function normalizeRecipe(raw, index, issues, warnings) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    issues.push(`recipes[${index}] is not an object`);
    return null;
  }

  if (typeof raw.id !== "string" || raw.id.trim() === "") {
    // A missing ID is a hard error: inventing one would make it impossible to
    // prove that the iOS record survived migration.
    issues.push(`recipes[${index}] is missing id; refusing to invent an identity`);
  }
  if (raw.createdAt !== undefined && !dateIsValid(raw.createdAt)) {
    issues.push(`recipes[${index}].createdAt is not a valid ISO date`);
  }
  if (raw.updatedAt !== undefined && !dateIsValid(raw.updatedAt)) {
    issues.push(`recipes[${index}].updatedAt is not a valid ISO date`);
  }
  if (raw.cookLogs !== undefined && !Array.isArray(raw.cookLogs)) {
    issues.push(`recipes[${index}].cookLogs must be an array`);
  }

  const cookLogs = (Array.isArray(raw.cookLogs) ? raw.cookLogs : [])
    .map((log, logIndex) => normalizeCookLog(log, logIndex, issues))
    .filter(Boolean);

  const recipe = {
    id: asString(raw.id, newUUID()),
    title: asString(raw.title),
    summary: asString(raw.summary),
    sourceURL: asString(raw.sourceURL),
    sourceHost: asString(raw.sourceHost),
    sourceImageURL: asOptionalString(raw.sourceImageURL),
    imagePath: asOptionalString(raw.imagePath),
    notes: asString(raw.notes),
    tags: normalizeTags(raw.tags),
    servings: asString(raw.servings),
    ingredients: normalizeLines(raw.ingredients),
    instructions: normalizeLines(raw.instructions),
    checkedIngredients: normalizeLines(raw.checkedIngredients),
    normalizedSourceURL: asString(raw.normalizedSourceURL, asString(raw.sourceURL)),
    sourceKind: sourceKindFor(raw.sourceURL, raw.sourceHost, asString(raw.sourceKind)),
    isFavorite: asBoolean(raw.isFavorite),
    rating: Math.max(0, Math.min(5, asInteger(raw.rating))),
    wantsRemake: asBoolean(raw.wantsRemake),
    extractedRawText: asString(raw.extractedRawText),
    rawImportedText: asString(raw.rawImportedText, asString(raw.extractedRawText)),
    rawImportedHTML: asString(raw.rawImportedHTML),
    importedTextSource: asString(raw.importedTextSource, "none"),
    extractionConfidence: asNumber(raw.extractionConfidence),
    extractionWarnings: normalizeLines(raw.extractionWarnings),
    ingredientSource: asString(raw.ingredientSource, "none"),
    instructionSource: asString(raw.instructionSource, "none"),
    createdAt: asString(raw.createdAt, new Date(0).toISOString()),
    updatedAt: asString(raw.updatedAt, asString(raw.createdAt, new Date(0).toISOString())),
    cookLogs,
    _unknownFields: unknownFields(raw, RECIPE_FIELDS),
    _providedFields: new Set(Object.keys(raw)),
  };

  if (!raw.title) warnings.push(`recipes[${index}] has no title`);
  return recipe;
}

function normalizeRoot(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new BackupValidationError("backup.json must contain a JSON object");
  }

  const issues = [];
  const warnings = [];
  if (!Array.isArray(value.recipes)) {
    throw new BackupValidationError("backup.json is missing the recipes array");
  }

  const requestedFormat = value.format;
  if (requestedFormat !== undefined && requestedFormat !== PORTABLE_FORMAT) {
    issues.push(`unsupported backup format: ${String(requestedFormat)}`);
  }

  const requestedSchema = value.schemaVersion ?? 1;
  if (!Number.isInteger(requestedSchema) || requestedSchema < 1 || requestedSchema > PORTABLE_SCHEMA_VERSION) {
    issues.push(`unsupported schemaVersion: ${String(requestedSchema)}`);
  }

  const recipes = value.recipes
    .map((recipe, index) => normalizeRecipe(recipe, index, issues, warnings))
    .filter(Boolean);
  const ids = new Set();
  recipes.forEach((recipe, index) => {
    if (ids.has(recipe.id)) issues.push(`duplicate recipe id: ${recipe.id}`);
    ids.add(recipe.id);
    recipe.cookLogs.forEach((log, logIndex) => {
      if (recipe.cookLogs.slice(0, logIndex).some((previous) => previous.id === log.id)) {
        issues.push(`duplicate cookLog id in recipe ${recipe.id}: ${log.id}`);
      }
    });
  });

  const payload = {
    format: PORTABLE_FORMAT,
    schemaVersion: PORTABLE_SCHEMA_VERSION,
    formatVersion: Number.isInteger(value.formatVersion) ? value.formatVersion : NATIVE_FORMAT_VERSION,
    exportedAt: dateIsValid(value.exportedAt) ? value.exportedAt : new Date(0).toISOString(),
    recipes,
    _unknownFields: unknownFields(value, ROOT_FIELDS),
  };
  // Keep root-level extension keys attached to the in-memory records so a
  // later Web export does not erase them after an iOS → Web → Web round-trip.
  recipes.forEach((recipe) => {
    recipe._rootUnknownFields = payload._unknownFields;
  });

  return { payload, issues, warnings };
}

export function parseBackupJSON(value) {
  const result = normalizeRoot(value);
  if (result.issues.length) {
    throw new BackupValidationError("This backup failed validation.", result.issues);
  }
  return result.payload;
}

export function inspectBackupJSON(value) {
  return normalizeRoot(value);
}

function fieldShouldBeEmitted(recipe, field, defaultValue) {
  if (recipe._providedFields?.has(field)) return true;
  const current = recipe[field];
  if (Array.isArray(defaultValue)) return Array.isArray(current) && current.length > 0;
  if (typeof defaultValue === "boolean") return current !== defaultValue;
  if (typeof defaultValue === "number") return current !== defaultValue;
  return current !== defaultValue && current !== null && current !== undefined;
}

function serializeCookLog(log) {
  const out = { ...(log._unknownFields ?? {}) };
  const fields = {
    id: log.id,
    cookedAt: log.cookedAt,
    memo: log.memo,
    imagePath: log.imagePath,
    rating: log.rating,
    improvementMemo: log.improvementMemo,
    arrangementMemo: log.arrangementMemo,
  };
  const defaults = {
    id: "",
    cookedAt: new Date(0).toISOString(),
    memo: "",
    imagePath: null,
    rating: 0,
    improvementMemo: "",
    arrangementMemo: "",
  };
  for (const [field, value] of Object.entries(fields)) {
    if (fieldShouldBeEmitted({ ...log, [field]: value }, field, defaults[field])) {
      out[field] = value;
    }
  }
  return out;
}

export function serializeRecipe(recipe) {
  const out = { ...(recipe._unknownFields ?? {}) };
  const fields = {
    id: recipe.id,
    title: recipe.title,
    summary: recipe.summary,
    sourceURL: recipe.sourceURL,
    sourceHost: recipe.sourceHost,
    sourceImageURL: recipe.sourceImageURL,
    imagePath: recipe.imagePath,
    notes: recipe.notes,
    tags: recipe.tags,
    servings: recipe.servings,
    ingredients: recipe.ingredients,
    instructions: recipe.instructions,
    checkedIngredients: recipe.checkedIngredients,
    normalizedSourceURL: recipe.normalizedSourceURL,
    sourceKind: recipe.sourceKind,
    isFavorite: recipe.isFavorite,
    rating: recipe.rating,
    wantsRemake: recipe.wantsRemake,
    extractedRawText: recipe.extractedRawText,
    rawImportedText: recipe.rawImportedText,
    rawImportedHTML: recipe.rawImportedHTML,
    importedTextSource: recipe.importedTextSource,
    extractionConfidence: recipe.extractionConfidence,
    extractionWarnings: recipe.extractionWarnings,
    ingredientSource: recipe.ingredientSource,
    instructionSource: recipe.instructionSource,
    createdAt: recipe.createdAt,
    updatedAt: recipe.updatedAt,
    cookLogs: recipe.cookLogs.map(serializeCookLog),
  };
  const defaults = {
    id: "",
    title: "",
    summary: "",
    sourceURL: "",
    sourceHost: "",
    sourceImageURL: null,
    imagePath: null,
    notes: "",
    tags: [],
    servings: "",
    ingredients: [],
    instructions: [],
    checkedIngredients: [],
    normalizedSourceURL: "",
    sourceKind: "web",
    isFavorite: false,
    rating: 0,
    wantsRemake: false,
    extractedRawText: "",
    rawImportedText: "",
    rawImportedHTML: "",
    importedTextSource: "none",
    extractionConfidence: 0,
    extractionWarnings: [],
    ingredientSource: "none",
    instructionSource: "none",
    createdAt: new Date(0).toISOString(),
    updatedAt: new Date(0).toISOString(),
    cookLogs: [],
  };
  for (const [field, value] of Object.entries(fields)) {
    if (fieldShouldBeEmitted(recipe, field, defaults[field])) out[field] = value;
  }
  return out;
}

export function makePortableBackup(recipes, exportedAt = new Date().toISOString()) {
  const rootExtras = recipes.find((recipe) => recipe._rootUnknownFields)?._rootUnknownFields ?? {};
  return {
    ...rootExtras,
    format: PORTABLE_FORMAT,
    schemaVersion: PORTABLE_SCHEMA_VERSION,
    formatVersion: NATIVE_FORMAT_VERSION,
    exportedAt,
    recipes: [...recipes]
      .sort((left, right) => String(left.createdAt).localeCompare(String(right.createdAt)))
      .map(serializeRecipe),
  };
}

export function backupJSONString(recipes, exportedAt = new Date().toISOString()) {
  return JSON.stringify(makePortableBackup(recipes, exportedAt), null, 2);
}

function comparableCookLog(log) {
  return {
    id: log.id,
    cookedAt: log.cookedAt,
    memo: log.memo,
    imagePath: log.imagePath,
    rating: log.rating,
    improvementMemo: log.improvementMemo,
    arrangementMemo: log.arrangementMemo,
    unknown: log._unknownFields ?? {},
  };
}

export function comparableRecipe(recipe) {
  return {
    id: recipe.id,
    title: recipe.title,
    summary: recipe.summary,
    sourceURL: recipe.sourceURL,
    sourceHost: recipe.sourceHost,
    sourceImageURL: recipe.sourceImageURL,
    imagePath: recipe.imagePath,
    notes: recipe.notes,
    tags: recipe.tags,
    servings: recipe.servings,
    ingredients: recipe.ingredients,
    instructions: recipe.instructions,
    checkedIngredients: recipe.checkedIngredients,
    normalizedSourceURL: recipe.normalizedSourceURL,
    sourceKind: recipe.sourceKind,
    isFavorite: recipe.isFavorite,
    rating: recipe.rating,
    wantsRemake: recipe.wantsRemake,
    extractedRawText: recipe.extractedRawText,
    rawImportedText: recipe.rawImportedText,
    rawImportedHTML: recipe.rawImportedHTML,
    importedTextSource: recipe.importedTextSource,
    extractionConfidence: recipe.extractionConfidence,
    extractionWarnings: recipe.extractionWarnings,
    ingredientSource: recipe.ingredientSource,
    instructionSource: recipe.instructionSource,
    createdAt: recipe.createdAt,
    updatedAt: recipe.updatedAt,
    cookLogs: recipe.cookLogs.map(comparableCookLog),
    unknown: recipe._unknownFields ?? {},
  };
}

function stableJSON(value) {
  if (Array.isArray(value)) return `[${value.map(stableJSON).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJSON(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function semanticDifferences(leftRecipes, rightRecipes) {
  const left = new Map(leftRecipes.map((recipe) => [recipe.id, comparableRecipe(recipe)]));
  const right = new Map(rightRecipes.map((recipe) => [recipe.id, comparableRecipe(recipe)]));
  const differences = [];
  for (const id of new Set([...left.keys(), ...right.keys()])) {
    if (!left.has(id)) differences.push(`missing on source: ${id}`);
    else if (!right.has(id)) differences.push(`missing on destination: ${id}`);
    else if (stableJSON(left.get(id)) !== stableJSON(right.get(id))) differences.push(`fields differ: ${id}`);
  }
  return differences;
}

export function validateRoundTrip(recipes) {
  const backup = makePortableBackup(recipes);
  const parsed = parseBackupJSON(backup);
  return {
    valid: semanticDifferences(recipes, parsed.recipes).length === 0,
    differences: semanticDifferences(recipes, parsed.recipes),
    recipeCount: recipes.length,
    recipeIds: recipes.map((recipe) => recipe.id),
  };
}

export function backupSummary(payload, imageNames = new Set()) {
  const referencedImages = new Set();
  payload.recipes.forEach((recipe) => {
    if (recipe.imagePath) referencedImages.add(recipe.imagePath);
    recipe.cookLogs.forEach((log) => {
      if (log.imagePath) referencedImages.add(log.imagePath);
    });
  });
  const missingImages = [...referencedImages].filter((name) => !imageNames.has(name));
  return {
    recipeCount: payload.recipes.length,
    recipeIds: payload.recipes.map((recipe) => recipe.id),
    cookLogCount: payload.recipes.reduce((sum, recipe) => sum + recipe.cookLogs.length, 0),
    referencedImageCount: referencedImages.size,
    missingImages,
    tagCount: new Set(payload.recipes.flatMap((recipe) => recipe.tags.map((tag) => tag.toLocaleLowerCase()))).size,
  };
}
