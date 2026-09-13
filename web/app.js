import {
  backupJSONString,
  backupSummary,
  dateIsValid,
  inspectBackupJSON,
  newUUID,
  normalizeLines,
  normalizeTags,
  validateRoundTrip,
} from "./portable.js";
import { createStoreZip, readStoreZip } from "./zip.js";
import {
  deleteRecipe,
  diagnostics,
  getImage,
  listRecipes,
  putImage,
  putRecipe,
  replaceAllData,
} from "./db.js";
import {
  ACHIEVEMENT_CATEGORIES,
  achievementProgress,
  achievementsFor,
  equippedTitle,
  nextAchievement,
  readSelectedTitle,
  titleMilestones,
  writeSelectedTitle,
} from "./achievements.js";

const app = document.querySelector("#app");
const textDecoder = new TextDecoder();
const textEncoder = new TextEncoder();

const FILTERS = [
  ["all", "すべて"],
  ["favorite", "お気に入り"],
  ["cooked", "作ったことあり"],
  ["notCooked", "まだ作ってない"],
  ["hasImage", "画像あり"],
  ["instagram", "Instagram"],
  ["cookpad", "Cookpad"],
  ["youtube", "YouTube"],
  ["web", "Web"],
  ["ratingFourPlus", "評価4以上"],
  ["wantsRemake", "また作りたい"],
];

const SORTS = [
  ["recentlyUpdated", "最近更新"],
  ["recentlyAdded", "最近追加"],
  ["recentlyCooked", "最近作った"],
  ["highRating", "評価が高い"],
  ["title", "タイトル順"],
];

const SOURCE_KINDS = [
  ["instagram", "Instagram"],
  ["cookpad", "Cookpad"],
  ["youtube", "YouTube"],
  ["web", "Web"],
  ["original", "自作"],
  ["image", "画像"],
  ["other", "その他"],
];

const THEME_OPTIONS = [
  ["system", "システムに合わせる"],
  ["light", "ライト"],
  ["dark", "ダーク"],
];

function readThemePreference() {
  try {
    const saved = localStorage.getItem("recipeclipper-theme");
    return THEME_OPTIONS.some(([value]) => value === saved) ? saved : "system";
  } catch {
    return "system";
  }
}

function readSortPreference() {
  try {
    const saved = localStorage.getItem("recipeclipper-sort");
    return SORTS.some(([value]) => value === saved) ? saved : "recentlyUpdated";
  } catch {
    return "recentlyUpdated";
  }
}

const state = {
  recipes: [],
  selectedId: null,
  query: "",
  filter: "all",
  tag: null,
  sort: readSortPreference(),
  achievementPage: null,
  selectedTitleID: readSelectedTitle(),
  modal: null,
  editorMode: "manual",
  urlPrefill: null,
  editingId: null,
  editingLogId: null,
  importPreview: null,
  validationReport: null,
  diagnostics: null,
  toast: null,
  busy: false,
  error: null,
  theme: readThemePreference(),
  printPayload: null,
};

const imageURLs = new Map();
let pendingImagePreviewURL = null;
let renderFrame = null;
let pendingSearchSelection = null;

function esc(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function attr(value) {
  return esc(value).replaceAll("\n", "&#10;");
}

function formatDate(value, options = { year: "numeric", month: "short", day: "numeric" }) {
  if (!dateIsValid(value)) return "日付不明";
  return new Intl.DateTimeFormat("ja-JP", options).format(new Date(value));
}

function formatDateTime(value) {
  if (!dateIsValid(value)) return "日付不明";
  return new Intl.DateTimeFormat("ja-JP", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}

function dateInputValue(value) {
  if (!dateIsValid(value)) return new Date().toISOString().slice(0, 10);
  return new Date(value).toISOString().slice(0, 10);
}

function dateFromInput(value) {
  if (!value) return new Date().toISOString();
  return new Date(`${value}T12:00:00`).toISOString();
}

function sourceLabel(kind) {
  return SOURCE_KINDS.find(([value]) => value === kind)?.[1] ?? kind ?? "Web";
}

function stars(rating) {
  const value = Math.max(0, Math.min(5, Number(rating) || 0));
  return `${"★".repeat(value)}${"☆".repeat(5 - value)}`;
}

function normalizeURL(value) {
  const trimmed = String(value ?? "").trim();
  if (!trimmed) return "";
  try {
    const url = new URL(trimmed);
    url.hash = "";
    return url.toString();
  } catch {
    return trimmed;
  }
}

function sourceHost(value) {
  try {
    return new URL(value).host;
  } catch {
    return "";
  }
}

function sourceKindFromURL(value) {
  const source = `${sourceHost(value)} ${value}`.toLocaleLowerCase();
  if (source.includes("instagram.com")) return "instagram";
  if (source.includes("cookpad.com")) return "cookpad";
  if (source.includes("youtube.com") || source.includes("youtu.be")) return "youtube";
  return source.trim() ? "web" : "original";
}

function applyTheme() {
  const root = document.documentElement;
  const followsDarkSystem = state.theme === "system" && globalThis.matchMedia?.("(prefers-color-scheme: dark)").matches;
  if (state.theme === "system") {
    delete root.dataset.theme;
    root.style.colorScheme = "light dark";
  } else {
    root.dataset.theme = state.theme;
    root.style.colorScheme = state.theme;
  }
  try {
    localStorage.setItem("recipeclipper-theme", state.theme);
  } catch {
    // Private browsing may deny localStorage; the in-memory setting still works.
  }
  const themeColor = document.querySelector('meta[name="theme-color"]');
  if (themeColor) themeColor.content = state.theme === "dark" || followsDarkSystem ? "#171614" : "#f7f4ee";
}

function recipeTags(recipe) {
  return Array.isArray(recipe.tags) ? recipe.tags : [];
}

function lastCookedAt(recipe) {
  return (recipe.cookLogs ?? [])
    .map((log) => log.cookedAt)
    .filter(dateIsValid)
    .sort()
    .at(-1) ?? null;
}

function totalCooks() {
  return state.recipes.reduce((sum, recipe) => sum + (recipe.cookLogs?.length ?? 0), 0);
}

function allTags() {
  const counts = new Map();
  state.recipes.flatMap(recipeTags).forEach((tag) => counts.set(tag, (counts.get(tag) ?? 0) + 1));
  return [...counts.entries()]
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0], "ja"))
    .map(([tag]) => tag);
}

function matchesFilter(recipe) {
  switch (state.filter) {
    case "favorite": return recipe.isFavorite;
    case "cooked": return recipe.cookLogs?.length > 0;
    case "notCooked": return !recipe.cookLogs?.length;
    case "hasImage": return Boolean(recipe.imagePath);
    case "instagram": return recipe.sourceKind === "instagram";
    case "cookpad": return recipe.sourceKind === "cookpad";
    case "youtube": return recipe.sourceKind === "youtube";
    case "web": return recipe.sourceKind === "web";
    case "ratingFourPlus": return (recipe.rating ?? 0) >= 4;
    case "wantsRemake": return recipe.wantsRemake;
    default: return true;
  }
}

function visibleRecipes() {
  const words = state.query.toLocaleLowerCase().split(/\s+/).filter(Boolean);
  const filtered = state.recipes.filter((recipe) => {
    if (!matchesFilter(recipe)) return false;
    if (state.tag && !recipeTags(recipe).some((tag) => tag.toLocaleLowerCase() === state.tag.toLocaleLowerCase())) return false;
    const searchable = [
      recipe.title,
      recipe.summary,
      recipe.notes,
      recipe.sourceHost,
      recipe.sourceURL,
      recipeTags(recipe).join(" "),
      recipe.servings,
      (recipe.ingredients ?? []).join(" "),
      (recipe.instructions ?? []).join(" "),
      sourceLabel(recipe.sourceKind),
    ].join(" ").toLocaleLowerCase();
    return words.every((word) => searchable.includes(word));
  });
  return filtered.sort((left, right) => {
    if (state.sort === "recentlyAdded") return String(right.createdAt).localeCompare(String(left.createdAt));
    if (state.sort === "recentlyCooked") return String(lastCookedAt(right) ?? "").localeCompare(String(lastCookedAt(left) ?? ""));
    if (state.sort === "highRating") return (right.rating ?? 0) - (left.rating ?? 0) || String(right.updatedAt).localeCompare(String(left.updatedAt));
    if (state.sort === "title") return String(left.title).localeCompare(String(right.title), "ja");
    return String(right.updatedAt).localeCompare(String(left.updatedAt));
  });
}

function imageMarkup(recipe, className = "") {
  const fallback = recipe.sourceImageURL ? ` data-fallback="${attr(recipe.sourceImageURL)}"` : "";
  const image = recipe.imagePath
    ? `<img class="recipe-image ${className}" data-image="${attr(recipe.imagePath)}"${fallback} alt="${attr(recipe.title)}">`
    : recipe.sourceImageURL
      ? `<img class="recipe-image ${className}" data-image=""${fallback} alt="${attr(recipe.title)}">`
      : `<div class="image-placeholder ${className}" aria-hidden="true"><span>✦</span></div>`;
  return `<div class="image-frame">${image}</div>`;
}

function headerMarkup({ detail = false } = {}) {
  return `
    <header class="topbar">
      <div class="topbar-leading">
        ${detail ? `<button class="icon-button" data-action="home" aria-label="レシピ一覧へ戻る">←</button>` : ""}
        <button class="brand-button" data-action="home" aria-label="RecipeClipper ホーム">
          <span class="brand-mark">⌁</span>
          <span>Recipe<span>Clipper</span></span>
        </button>
      </div>
      <div class="topbar-actions">
        ${detail ? `<button class="button button-quiet" data-action="edit-recipe">編集</button>` : ""}
        <button class="icon-button" data-action="settings" aria-label="設定とバックアップ">⚙</button>
      </div>
    </header>`;
}

function achievementHeaderMarkup(title) {
  return `
    <header class="topbar achievement-topbar">
      <div class="topbar-leading">
        <button class="icon-button" data-action="home" aria-label="レシピ一覧へ戻る">←</button>
        <div class="page-title-lockup"><span class="eyebrow">KITCHEN JOURNEY</span><strong>${esc(title)}</strong></div>
      </div>
      <div class="topbar-actions">
        <button class="icon-button" data-action="settings" aria-label="設定とバックアップ">⚙</button>
      </div>
    </header>`;
}

function filterChips() {
  return FILTERS.map(([value, label]) => `
    <button class="chip ${state.filter === value ? "chip-active" : ""}" data-action="filter" data-filter="${value}">${label}</button>
  `).join("");
}

function tagChips() {
  const tags = allTags();
  if (!tags.length) return "";
  return `
    <div class="tag-row" aria-label="タグで絞り込む">
      ${tags.map((tag) => `<button class="chip chip-tag ${state.tag === tag ? "chip-tag-active" : ""}" data-action="tag" data-tag="${attr(tag)}"># ${esc(tag)}</button>`).join("")}
    </div>`;
}

function tagEditorSuggestions(recipe) {
  const existing = new Set(recipeTags(recipe).map((tag) => tag.toLocaleLowerCase()));
  const suggestions = allTags().filter((tag) => !existing.has(tag.toLocaleLowerCase())).slice(0, 8);
  if (!suggestions.length) return "";
  return `<div class="tag-suggestion-row" aria-label="よく使うタグ">${suggestions.map((tag) => `<button type="button" class="chip chip-tag" data-action="append-tag" data-tag="${attr(tag)}">＋ ${esc(tag)}</button>`).join("")}</div>`;
}

function statsMarkup() {
  const cookedRecipes = state.recipes.filter((recipe) => recipe.cookLogs?.length).length;
  const favoriteCount = state.recipes.filter((recipe) => recipe.isFavorite).length;
  const achievements = achievementsFor(state.recipes);
  const progress = achievementProgress(achievements);
  const next = nextAchievement(achievements);
  const spotlight = next ?? achievements.at(-1);
  return `
    <section class="intro-panel">
      <div class="eyebrow">PERSONAL COOKING ARCHIVE</div>
      <h1>大切なレシピを、<br><em>いつでも</em>手元に。</h1>
      <p>通信がなくても、あなたの料理帖はここにあります。</p>
      <div class="stat-strip">
        <span><strong>${state.recipes.length}</strong>品</span>
        <span><strong>${totalCooks()}</strong>回作った</span>
        <span><strong>${cookedRecipes}</strong>品を調理済み</span>
        <span><strong>${favoriteCount}</strong>お気に入り</span>
      </div>
      <button class="achievement-spotlight" data-action="achievements">
        <span class="achievement-spotlight-icon">${achievementGlyph(spotlight?.symbol ?? "trophy.fill")}</span>
        <span class="achievement-spotlight-copy"><span class="eyebrow">KITCHEN JOURNEY</span><strong>${spotlight?.isUnlocked ? "すべての実績を達成しました" : `次の実績：${esc(spotlight?.title ?? "キッチンの軌跡")}`}</strong><small>${progress.unlocked} / ${progress.total} 実績 ・ キッチンの軌跡を見る</small></span>
        <span class="achievement-spotlight-arrow">›</span>
      </button>
    </section>`;
}

function achievementGlyph(symbol) {
  const glyphs = {
    "archivebox.fill": "▣",
    "bookmark.fill": "🔖",
    "book.closed.fill": "▤",
    "books.vertical.fill": "▥",
    "building.columns.fill": "▥",
    "camera.fill": "◉",
    "calendar.badge.checkmark": "✓",
    "calendar.circle.fill": "◷",
    checklist: "☷",
    "circle.grid.3x3.fill": "⠿",
    "flame.circle.fill": "♨",
    "flame.fill": "♨",
    "fork.knife": "♜",
    "frying.pan.fill": "◒",
    "hand.thumbsup.fill": "☝",
    "heart.circle.fill": "♥",
    "heart.fill": "♥",
    "house.and.flag.fill": "⌂",
    "leaf.fill": "✦",
    map: "⌁",
    "map.fill": "⌁",
    medal: "✹",
    "medal.fill": "✹",
    note: "▤",
    "note.text": "▤",
    "pencil.and.scribble": "✎",
    "pencil.line": "✎",
    "photo.on.rectangle.angled": "▧",
    "photo.stack.fill": "▧",
    repeat: "↻",
    "repeat.circle.fill": "↻",
    safari: "✥",
    "safari.fill": "✥",
    sparkles: "✦",
    stars: "✦",
    "square.grid.2x2.fill": "⊞",
    "star.circle.fill": "★",
    "star.fill": "★",
    "sun.max.fill": "☼",
    "tag.circle.fill": "♢",
    "tag.fill": "♢",
    trophy: "♛",
    "trophy.fill": "♛",
    "text.book.closed.fill": "▤",
    "table.furniture.fill": "▦",
  };
  return glyphs[symbol] ?? "✦";
}

function achievementProgressBar(current, target, className = "") {
  const ratio = target > 0 ? Math.min(current / target, 1) : 1;
  return `<div class="achievement-progress ${className}" aria-hidden="true"><span style="width:${Math.round(ratio * 100)}%"></span></div>`;
}

function achievementCardMarkup(achievement) {
  return `
    <article class="achievement-card tone-${achievement.tone} ${achievement.isUnlocked ? "is-unlocked" : "is-locked"}">
      <div class="achievement-card-top"><span class="achievement-medallion">${achievementGlyph(achievement.symbol)}</span><span class="achievement-status">${achievement.isUnlocked ? "✓" : "🔒"}</span></div>
      <span class="achievement-eyebrow">${esc(achievement.eyebrow)}</span>
      <h3>${esc(achievement.title)}</h3>
      <p>${esc(achievement.detail)}</p>
      <div class="achievement-card-progress"><span>${esc(achievement.progressText)}</span><span>${achievement.isUnlocked ? "達成" : `${Math.round(achievement.progress * 100)}%`}</span></div>
      ${achievementProgressBar(achievement.current, achievement.target)}
    </article>`;
}

function achievementSeriesMarkup(category, achievements) {
  const items = achievements.filter((achievement) => achievement.category === category.id);
  const unlocked = items.filter((achievement) => achievement.isUnlocked).length;
  return `
    <section class="achievement-series">
      <div class="achievement-series-heading"><div><span class="achievement-category-symbol">${achievementGlyph(category.symbol)}</span><span class="eyebrow">${esc(category.subtitle)}</span><h2>${esc(category.title)}</h2></div><span class="achievement-series-count">${unlocked} / ${items.length}</span></div>
      <div class="achievement-grid">${items.map(achievementCardMarkup).join("")}</div>
    </section>`;
}

function achievementsView() {
  const achievements = achievementsFor(state.recipes);
  const progress = achievementProgress(achievements);
  const currentTitle = equippedTitle(achievements, state.selectedTitleID);
  const next = nextAchievement(achievements);
  return `
    ${achievementHeaderMarkup("キッチンの軌跡")}
    <main class="achievement-page">
      <section class="achievement-cabinet-hero">
        <div class="achievement-ring" style="--progress:${Math.round(progress.ratio * 100)}%"><span>${progress.unlocked}<small>/${progress.total}</small></span></div>
        <div class="achievement-cabinet-copy"><span class="eyebrow">CURRENT KITCHEN TITLE</span><h1>${esc(currentTitle.name)}</h1><p>料理の記録から、あなたの台所の歩みを集めています。</p><button class="button button-quiet achievement-title-link" data-action="titles">称号図鑑を見る ›</button></div>
      </section>
      ${next ? `<section class="achievement-next-card"><div class="achievement-next-icon tone-${next.tone}">${achievementGlyph(next.symbol)}</div><div class="achievement-next-copy"><span class="eyebrow">NEXT ACHIEVEMENT</span><h2>${esc(next.title)}</h2><p>${esc(next.detail)}</p>${achievementProgressBar(next.current, next.target)}<small>${esc(next.progressText)} ・ もう少しで解禁</small></div></section>` : `<section class="achievement-next-card all-unlocked"><div class="achievement-next-icon tone-gold">♛</div><div class="achievement-next-copy"><span class="eyebrow">ALL ACHIEVEMENTS</span><h2>台所の伝説</h2><p>38個すべての実績を達成しました。</p><small>料理の記録を続けて、あなたの料理帖を育てましょう。</small></div></section>`}
      <section class="achievement-total-line"><span><strong>${progress.unlocked}</strong> / ${progress.total} 実績</span><span>達成率 ${Math.round(progress.ratio * 100)}%</span></section>
      ${ACHIEVEMENT_CATEGORIES.map((category) => achievementSeriesMarkup(category, achievements)).join("")}
    </main>
    ${state.modal ? modalMarkup() : ""}`;
}

function titleGroupMarkup(group, milestones) {
  const groupMeta = {
    journey: ["料理人の歩み", "勲章の総獲得数で解禁"],
    specialist: ["シリーズ特化", "ひとつの分野を深く究めて解禁"],
    mastery: ["シリーズ制覇", "シリーズの勲章をすべて集めて解禁"],
  }[group];
  return `<section class="title-group"><div class="title-group-heading"><div><span class="eyebrow">${esc(group.toUpperCase())}</span><h2>${esc(groupMeta[0])}</h2><p>${esc(groupMeta[1])}</p></div></div><div class="title-list">${milestones.filter((milestone) => milestone.group === group).map((milestone) => `<button class="title-row ${milestone.isUnlocked ? "is-unlocked" : "is-locked"} ${state.selectedTitleID === milestone.title.id ? "is-equipped" : ""}" data-action="equip-title" data-title-id="${attr(milestone.title.id)}" ${milestone.isUnlocked ? "" : "disabled"}><span class="title-row-icon tone-${milestone.title.tone}">${achievementGlyph(milestone.title.symbol)}</span><span class="title-row-copy"><strong>${esc(milestone.title.name)}</strong><small>${esc(milestone.condition)}</small>${achievementProgressBar(milestone.current, milestone.target)}</span><span class="title-row-status">${state.selectedTitleID === milestone.title.id ? "装備中" : milestone.isUnlocked ? "解禁" : esc(milestone.progressText)}</span></button>`).join("")}</div></section>`;
}

function titlesView() {
  const achievements = achievementsFor(state.recipes);
  const currentTitle = equippedTitle(achievements, state.selectedTitleID);
  const milestones = titleMilestones(achievements);
  return `
    ${achievementHeaderMarkup("称号図鑑")}
    <main class="achievement-page titles-page">
      <section class="equipped-title-card tone-${currentTitle.tone}"><span class="equipped-title-icon">${achievementGlyph(currentTitle.symbol)}</span><div><span class="eyebrow">EQUIPPED KITCHEN TITLE</span><h1>${esc(currentTitle.name)}</h1><p>解禁した称号を選ぶと、キッチンの軌跡に表示できます。</p></div><button class="button button-quiet" data-action="achievements">実績一覧へ</button></section>
      ${titleGroupMarkup("journey", milestones)}
      ${titleGroupMarkup("specialist", milestones)}
      ${titleGroupMarkup("mastery", milestones)}
    </main>
    ${state.modal ? modalMarkup() : ""}`;
}

function printImageMarkup(recipe) {
  if (!recipe.imagePath && !recipe.sourceImageURL) return "";
  const fallback = recipe.sourceImageURL ? ` data-fallback="${attr(recipe.sourceImageURL)}"` : "";
  return `<img class="print-recipe-image" data-image="${attr(recipe.imagePath ?? "")}"${fallback} alt="${attr(recipe.title)}">`;
}

function printRecipeMarkup(recipe) {
  const logs = [...(recipe.cookLogs ?? [])].sort((left, right) => String(right.cookedAt).localeCompare(String(left.cookedAt)));
  return `<article class="print-recipe">
    <header class="print-recipe-header"><div><span class="eyebrow">${esc(sourceLabel(recipe.sourceKind))}</span><h2>${esc(recipe.title || "無題のレシピ")}</h2>${recipe.summary ? `<p>${esc(recipe.summary)}</p>` : ""}</div>${printImageMarkup(recipe)}</header>
    ${recipe.servings ? `<p class="print-servings">${esc(recipe.servings)}</p>` : ""}
    <div class="print-recipe-columns"><section><h3>材料</h3>${recipe.ingredients?.length ? `<ul>${recipe.ingredients.map((line) => `<li>${esc(line)}</li>`).join("")}</ul>` : `<p>材料情報なし</p>`}</section><section><h3>作り方</h3>${recipe.instructions?.length ? `<ol>${recipe.instructions.map((line) => `<li>${esc(line)}</li>`).join("")}</ol>` : `<p>作り方情報なし</p>`}</section></div>
    ${recipe.notes || recipeTags(recipe).length ? `<section class="print-notes"><h3>メモとタグ</h3>${recipe.notes ? `<p>${esc(recipe.notes)}</p>` : ""}${recipeTags(recipe).length ? `<p>${recipeTags(recipe).map((tag) => `#${esc(tag)}`).join("　")}</p>` : ""}</section>` : ""}
    ${logs.length ? `<section class="print-logs"><h3>作った記録</h3>${logs.map((log) => `<div class="print-log"><strong>${esc(formatDate(log.cookedAt))}</strong>${log.rating ? `　${stars(log.rating)}` : ""}${log.memo ? `<p>メモ：${esc(log.memo)}</p>` : ""}${log.arrangementMemo ? `<p>アレンジ：${esc(log.arrangementMemo)}</p>` : ""}${log.improvementMemo ? `<p>次回改善：${esc(log.improvementMemo)}</p>` : ""}</div>`).join("")}</section>` : ""}
  </article>`;
}

function printView(recipes) {
  return `<main class="print-document"><header class="print-document-header"><span class="eyebrow">RECIPECLIPPER · PERSONAL COOKING ARCHIVE</span><h1>わたしの料理帖</h1><p>${recipes.length}品 ・ ${formatDateTime(new Date().toISOString())} 出力</p></header>${recipes.map(printRecipeMarkup).join("")}</main>`;
}

function recipeCard(recipe, featured = false) {
  const tags = recipeTags(recipe).slice(0, 3).map((tag) => `#${esc(tag)}`).join(" ");
  return `
    <article class="recipe-card ${featured ? "recipe-card-featured" : ""}">
      <button class="card-main" data-action="recipe" data-id="${attr(recipe.id)}">
        ${imageMarkup(recipe, featured ? "featured-image" : "card-image")}
        <span class="card-overlay"></span>
        <span class="card-copy">
          <span class="source-pill">${esc(sourceLabel(recipe.sourceKind))}</span>
          <strong>${esc(recipe.title || "無題のレシピ")}</strong>
          ${featured && recipe.summary ? `<span class="card-summary">${esc(recipe.summary)}</span>` : ""}
          <span class="card-meta">
            ${recipe.rating ? `<span class="stars">${stars(recipe.rating)}</span>` : `<span>${esc(recipe.sourceHost || "RecipeClipper")}</span>`}
            ${lastCookedAt(recipe) ? `<span>作った: ${esc(formatDate(lastCookedAt(recipe)))}</span>` : ""}
          </span>
          ${tags ? `<span class="card-tags">${tags}</span>` : ""}
        </span>
        ${recipe.isFavorite ? `<span class="card-badge badge-heart">♥</span>` : ""}
        ${recipe.wantsRemake ? `<span class="card-badge badge-remake">↺</span>` : ""}
      </button>
    </article>`;
}

function listView() {
  const recipes = visibleRecipes();
  const featured = recipes[0];
  const rest = recipes.slice(1);
  const selectedSort = SORTS.find(([value]) => value === state.sort)?.[1] ?? "最近更新";
  return `
    ${headerMarkup()}
    <main class="page list-page">
      ${statsMarkup()}
      <section class="toolbar-card">
        <label class="search-box">
          <span aria-hidden="true">⌕</span>
          <input data-role="search" type="search" value="${attr(state.query)}" placeholder="料理名・タグ・材料・メモで検索" autocomplete="off">
          ${state.query ? `<button class="search-clear" data-action="clear-search" aria-label="検索を消去">×</button>` : ""}
        </label>
        <div class="sort-line">
          <span class="muted-label">${recipes.length}件表示</span>
          <label class="sort-select">並び順
            <select data-role="sort" aria-label="並び順">
              ${SORTS.map(([value, label]) => `<option value="${value}" ${state.sort === value ? "selected" : ""}>${label}</option>`).join("")}
            </select>
          </label>
        </div>
        <div class="chip-row" aria-label="レシピを絞り込む">${filterChips()}</div>
        ${tagChips()}
      </section>
      ${state.error ? `<div class="error-banner">${esc(state.error)}</div>` : ""}
      ${state.recipes.length === 0 ? emptyState() : recipes.length === 0 ? noResultsState() : `
        <section class="recipe-feed">
          ${featured ? recipeCard(featured, true) : ""}
          ${rest.length ? `<div class="recipe-grid">${rest.map((recipe) => recipeCard(recipe)).join("")}</div>` : ""}
        </section>`}
    </main>
    <button class="floating-add" data-action="add-recipe" aria-label="レシピを追加">＋<span>追加</span></button>
    ${state.modal ? modalMarkup() : ""}`;
}

function emptyState() {
  return `<section class="empty-state"><div class="empty-icon">✦</div><h2>まだレシピがありません</h2><p>自分で書いたレシピや、iPhone版から書き出した<br>バックアップをここへ保存できます。</p><button class="button button-primary" data-action="add-recipe">最初のレシピを追加</button><button class="button button-secondary" data-action="settings">バックアップを読み込む</button></section>`;
}

function noResultsState() {
  return `<section class="empty-state compact"><div class="empty-icon">⌕</div><h2>該当するレシピがありません</h2><p>検索語やフィルタを変更してください。</p><button class="button button-secondary" data-action="reset-filters">絞り込みをリセット</button></section>`;
}

function detailView(recipe) {
  if (!recipe) {
    state.selectedId = null;
    return listView();
  }
  const checked = new Set(recipe.checkedIngredients ?? []);
  const logs = [...(recipe.cookLogs ?? [])].sort((left, right) => String(right.cookedAt).localeCompare(String(left.cookedAt)));
  const rawAvailable = recipe.rawImportedText || recipe.rawImportedHTML || recipe.extractionWarnings?.length;
  return `
    ${headerMarkup({ detail: true })}
    <main class="page detail-page">
      <section class="detail-hero">
        ${imageMarkup(recipe, "detail-image")}
        <div class="detail-hero-copy">
          <div class="detail-pills"><span class="source-pill">${esc(sourceLabel(recipe.sourceKind))}</span>${recipe.sourceHost ? `<span class="host-pill">${esc(recipe.sourceHost)}</span>` : ""}</div>
          <h1>${esc(recipe.title || "無題のレシピ")}</h1>
          ${recipe.summary ? `<p>${esc(recipe.summary)}</p>` : ""}
          <div class="detail-actions">
            <button class="toggle-button ${recipe.isFavorite ? "is-on favorite" : ""}" data-action="toggle-favorite" data-id="${attr(recipe.id)}">♥ <span>お気に入り</span></button>
            <button class="toggle-button ${recipe.wantsRemake ? "is-on remake" : ""}" data-action="toggle-remake" data-id="${attr(recipe.id)}">↺ <span>また作りたい</span></button>
            <button class="toggle-button" data-action="share-recipe" data-id="${attr(recipe.id)}">↗ <span>共有</span></button>
            <button class="toggle-button" data-action="print-recipe" data-id="${attr(recipe.id)}">▤ <span>PDF/印刷</span></button>
          </div>
          <div class="rating-line"><span>評価</span>${ratingControl(recipe.rating, recipe.id)}</div>
          <div class="meta-line">${recipe.cookLogs?.length ?? 0}回作成${lastCookedAt(recipe) ? ` ・ 最終: ${esc(formatDate(lastCookedAt(recipe)))}` : ""}</div>
          ${recipe.sourceURL ? `<a class="source-link" href="${attr(recipe.sourceURL)}" target="_blank" rel="noreferrer">元レシピを開く ↗</a>` : ""}
        </div>
      </section>
      <section class="detail-section ingredients-section">
        <div class="section-heading"><div><span class="section-kicker green">INGREDIENTS</span><h2>材料</h2></div>${recipe.servings ? `<span class="servings-pill">♟ ${esc(recipe.servings)}</span>` : ""}</div>
        ${recipe.ingredients?.length ? `
          <div class="check-progress"><span>${[...checked].filter((line) => recipe.ingredients.includes(line)).length}/${recipe.ingredients.length} チェック済み</span><button data-action="reset-checklist" data-id="${attr(recipe.id)}">リセット</button></div>
          <div class="ingredient-list">${recipe.ingredients.map((line, index) => `<button class="ingredient-row ${checked.has(line) ? "is-checked" : ""}" data-action="toggle-ingredient" data-id="${attr(recipe.id)}" data-index="${index}"><span class="check-circle">${checked.has(line) ? "✓" : ""}</span><span>${esc(line)}</span></button>`).join("")}</div>` : `<p class="empty-detail">材料情報なし</p>`}
      </section>
      <section class="detail-section instructions-section">
        <div class="section-heading"><div><span class="section-kicker tomato">METHOD</span><h2>作り方</h2></div></div>
        ${recipe.instructions?.length ? `<ol class="instruction-list">${recipe.instructions.map((line, index) => `<li><span class="step-number">${index + 1}</span><span>${esc(line)}</span></li>`).join("")}</ol>` : `<p class="empty-detail">作り方情報なし</p>`}
      </section>
      ${(recipe.notes || recipeTags(recipe).length) ? `<section class="detail-section notes-section"><div class="section-heading"><div><span class="section-kicker indigo">PERSONAL NOTES</span><h2>メモとタグ</h2></div></div>${recipe.notes ? `<p class="note-text">${esc(recipe.notes)}</p>` : ""}${recipeTags(recipe).length ? `<div class="detail-tags">${recipeTags(recipe).map((tag) => `<span># ${esc(tag)}</span>`).join("")}</div>` : ""}</section>` : ""}
      <section class="detail-section logs-section">
        <div class="section-heading"><div><span class="section-kicker ember">COOKING JOURNAL</span><h2>作った記録</h2></div><button class="button button-small button-outline" data-action="add-cook-log" data-id="${attr(recipe.id)}">＋ 記録を追加</button></div>
        ${logs.length ? `<div class="log-list">${logs.map((log) => cookLogMarkup(recipe, log)).join("")}</div>` : `<p class="empty-detail">まだ作った記録がありません</p>`}
      </section>
      ${rawAvailable ? `<details class="raw-details"><summary>取得した元本文・抽出情報</summary><div class="raw-content">${recipe.rawImportedText ? `<pre>${esc(recipe.rawImportedText)}</pre>` : ""}${recipe.importedTextSource ? `<p>取得元: ${esc(recipe.importedTextSource)}</p>` : ""}${recipe.extractionWarnings?.length ? `<p>注意: ${recipe.extractionWarnings.map(esc).join(" / ")}</p>` : ""}</div></details>` : ""}
      <section class="detail-footer"><button class="danger-link" data-action="delete-recipe" data-id="${attr(recipe.id)}">このレシピを削除</button><span>登録: ${esc(formatDateTime(recipe.createdAt))} ・ 更新: ${esc(formatDateTime(recipe.updatedAt))}</span></section>
    </main>
    ${state.modal ? modalMarkup() : ""}`;
}

function ratingControl(rating, id, logId = "") {
  return `<span class="rating-control">${[1, 2, 3, 4, 5].map((value) => `<button type="button" class="rating-star ${value <= (rating ?? 0) ? "selected" : ""}" data-action="set-rating" data-id="${attr(id)}" data-log-id="${attr(logId)}" data-rating="${value}" aria-label="評価${value}">★</button>`).join("")}</span>`;
}

function cookLogMarkup(recipe, log) {
  const photo = log.imagePath
    ? `<div class="log-image"><img class="recipe-image" data-image="${attr(log.imagePath)}" alt="作った記録の写真"></div>`
    : `<div class="log-image log-image-placeholder">♨</div>`;
  return `<article class="cook-log-card">
    <div class="log-top">
      ${photo}
      <div><strong>${esc(formatDate(log.cookedAt))}</strong>${log.rating ? `<div class="stars">${stars(log.rating)}</div>` : ""}</div>
    <span class="log-menu"><button class="icon-button small" data-action="edit-cook-log" data-id="${attr(recipe.id)}" data-log-id="${attr(log.id)}" aria-label="記録を編集">⋯</button><button class="icon-button small" data-action="delete-cook-log" data-id="${attr(recipe.id)}" data-log-id="${attr(log.id)}" aria-label="記録を削除">⌫</button></span>
    </div>
    ${log.memo ? `<div class="log-field"><span>メモ</span><p>${esc(log.memo)}</p></div>` : ""}
    ${log.arrangementMemo ? `<div class="log-field"><span>アレンジ</span><p>${esc(log.arrangementMemo)}</p></div>` : ""}
    ${log.improvementMemo ? `<div class="log-field"><span>次回改善</span><p>${esc(log.improvementMemo)}</p></div>` : ""}
  </article>`;
}

function modalShell(title, content, wide = false, variant = "") {
  return `<div class="modal-backdrop" data-action="close-modal"><section class="modal-card ${wide ? "modal-wide" : ""} ${variant}" role="dialog" aria-modal="true" aria-label="${attr(title)}" data-modal-card><div class="modal-header"><h2>${esc(title)}</h2><button class="icon-button" data-action="close-modal" aria-label="閉じる">×</button></div>${content}</section></div>`;
}

function modalMarkup() {
  if (state.modal === "settings") return settingsModal();
  if (state.modal === "add-method") return addMethodModal();
  if (state.modal === "url-import") return urlImportModal();
  if (state.modal === "recipe") return recipeModal();
  if (state.modal === "cooklog") return cookLogModal();
  return "";
}

function urlImportModal() {
  return modalShell("URLから取り込む", `
    <form class="editor-form url-import-form" data-form="url-import">
      <div class="form-section url-import-hero"><div class="method-icon method-icon-indigo">↗</div><div><strong>リンクを貼るだけ</strong><p>URLを元レシピとして保存し、内容を確認しながら入力できます。</p></div></div>
      <div class="form-section"><label class="field-label">レシピURL <span class="required">必須</span><input name="sourceURL" type="url" required placeholder="https://example.com/recipe" autocomplete="url" autocapitalize="none"></label><label class="field-label">本文を貼り付け（任意）<textarea name="rawImportedText" data-field="raw" rows="8" placeholder="InstagramのキャプションやWebページ本文を貼り付け">${esc(state.urlPrefill?.rawImportedText ?? "")}</textarea></label><p class="editor-help">外部サイトが自動取得を許可していない場合も、URLと貼り付けた本文を保存できます。材料・作り方は次の画面で手直ししてください。</p></div>
      <div class="form-actions"><button type="button" class="button button-quiet" data-action="close-modal">戻る</button><button type="submit" class="button button-primary">このURLでレシピを書く</button></div>
    </form>`, true, "modal-editor");
}

function addMethodModal() {
  return modalShell("新しいレシピ", `
    <div class="add-method-page">
      <div class="add-method-intro">
        <h3>新しいレシピ</h3>
        <p>いちばん近い追加方法を選んでください</p>
      </div>
      <button class="add-method-card" data-action="choose-add-mode" data-mode="manual">
        <span class="method-icon method-icon-tomato">✎</span>
        <span class="method-copy"><strong>自分でレシピを書く</strong><small>材料と手順を少しずつ。写真もきれいに登録できます</small></span>
        <span class="method-chevron">›</span>
      </button>
      <button class="add-method-card" data-action="choose-add-mode" data-mode="image">
        <span class="method-icon method-icon-basil">▧</span>
        <span class="method-copy"><strong>画像からレシピ</strong><small>スクリーンショットを選び、代表画像として保存します</small></span>
        <span class="method-chevron">›</span>
      </button>
      <button class="add-method-card" data-action="choose-add-mode" data-mode="url">
        <span class="method-icon method-icon-indigo">↗</span>
        <span class="method-copy"><strong>URLから取り込む</strong><small>Webページ、Instagram、YouTubeのレシピに</small></span>
        <span class="method-chevron">›</span>
      </button>
      <p class="privacy-note">画像はこの端末内に保存され、サーバーへ送信されません。</p>
    </div>`, true, "modal-method");
}

function settingsModal() {
  const preview = state.importPreview;
  const report = state.validationReport;
  const stats = state.diagnostics;
  const previewSummary = preview?.summary;
  const previewWarnings = [...(preview?.warnings ?? []), ...(previewSummary?.missingImages?.length ? [`画像 ${previewSummary.missingImages.length}件がZIP内にありません`] : [])];
  return modalShell("設定 / Backup", `
    <div class="settings-stack">
      <section class="settings-hero"><span class="settings-icon">⌘</span><div><h3>local-first RecipeClipper</h3><p>レシピはこの端末のIndexedDBに保存され、サーバーへ送信されません。</p></div></section>
      <section class="settings-card appearance-card"><div class="settings-card-heading"><div><span class="section-kicker indigo">APPEARANCE</span><h3>表示</h3></div></div><label class="field-label appearance-field">テーマ<select data-role="theme" aria-label="テーマ">${THEME_OPTIONS.map(([value, label]) => `<option value="${value}" ${state.theme === value ? "selected" : ""}>${label}</option>`).join("")}</select></label><p>元のiPhone版と同じく、初期状態は端末のライト／ダーク設定に合わせます。</p></section>
      <section class="settings-card"><div class="settings-card-heading"><div><span class="section-kicker tomato">BACKUP</span><h3>データを守る</h3></div><span class="backup-badge">portable</span></div><p>iPhone版のZIP、またはWeb版のZIPを読み込みます。復元は現在のデータを置き換えます。</p><div class="button-row"><button class="button button-primary" data-action="export-backup" ${state.busy ? "disabled" : ""}>↓ バックアップを書き出す</button><button class="button button-secondary" data-action="choose-backup" ${state.busy ? "disabled" : ""}>↑ バックアップを読み込む</button><button class="button button-quiet" data-action="print-all">▤ 全レシピをPDF/印刷</button></div><input id="backup-file" type="file" accept=".zip,.json,application/zip,application/json" hidden></section>
      ${preview ? `<section class="import-preview"><div class="preview-heading"><div><span class="section-kicker green">IMPORT CHECK</span><h3>復元前の検証結果</h3></div><span class="validation-pill ${preview.roundTrip?.valid && !preview.errors?.length ? "valid" : "invalid"}">${preview.roundTrip?.valid && !preview.errors?.length ? "検証OK" : "要確認"}</span></div><div class="preview-stats"><span><strong>${previewSummary.recipeCount}</strong>レシピ</span><span><strong>${previewSummary.cookLogCount}</strong>CookLog</span><span><strong>${previewSummary.tagCount}</strong>タグ</span><span><strong>${previewSummary.recipeIds.length}</strong>ID保持</span></div>${preview.errors?.length ? `<div class="validation-errors">${preview.errors.map((item) => `<p>⚠ ${esc(item)}</p>`).join("")}</div>` : ""}${previewWarnings.length ? `<div class="validation-warnings">${previewWarnings.map((item) => `<p>• ${esc(item)}</p>`).join("")}</div>` : ""}${preview.roundTrip?.differences?.length ? `<div class="validation-errors">${preview.roundTrip.differences.map((item) => `<p>⚠ ${esc(item)}</p>`).join("")}</div>` : ""}<p class="preview-note">同じバックアップを再度読み込んでもID単位で置き換わるため、二重登録されません。</p><div class="button-row"><button class="button button-danger" data-action="restore-backup" ${preview.errors?.length || !preview.roundTrip?.valid ? "disabled" : ""}>この内容で上書き復元</button><button class="button button-quiet" data-action="discard-import">キャンセル</button></div></section>` : ""}
      <section class="settings-card"><div class="settings-card-heading"><div><span class="section-kicker indigo">VALIDATION</span><h3>移行データを点検</h3></div></div><p>現在のIndexedDBをportable JSONへ変換し、再読込して件数・ID・配列順・全フィールドの意味が一致するか確認します。</p><button class="button button-secondary" data-action="validate-current">現在のデータを検証する</button>${report ? `<div class="validation-result ${report.valid ? "success" : "failure"}">${report.valid ? `✓ ${report.recipeCount}件のsemantic equivalenceを確認しました。` : `⚠ 差分 ${report.differences.length}件: ${report.differences.map(esc).join(" / ")}`}</div>` : ""}</section>
      <section class="settings-card compact-card"><div class="settings-card-heading"><div><span class="section-kicker ember">THIS DEVICE</span><h3>保存状態</h3></div></div>${stats ? `<div class="diagnostic-grid"><span>レシピ <strong>${stats.recipeCount}</strong></span><span>CookLog <strong>${stats.cookLogCount}</strong></span><span>画像 <strong>${stats.imageCount}</strong></span><span>DB v${stats.databaseVersion}</span></div>` : `<p>読み込み中…</p>`}</section>
      <details class="migration-help"><summary>iPhoneから移行する手順</summary><ol><li>iPhone版RecipeClipperで、右上の「…」→「バックアップを書き出し」を選びます。</li><li>FilesでZIPをiCloud DriveまたはAirDrop経由で、このSafariから選べる場所へ置きます。</li><li>この画面の「バックアップを読み込む」からZIPを選び、検証結果を確認して復元します。</li><li>復元後、件数・代表画像・材料・手順・CookLogを確認し、Web版からもう一度バックアップを書き出します。</li></ol></details>
    </div>`, true);
}

function editorPhotoSection(recipe, mode, editing) {
  const allowMultiple = !editing && mode === "image";
  const preview = recipe.imagePath
    ? imageMarkup(recipe, "editor-photo-image")
    : `<div class="editor-photo-placeholder"><span>♧</span><small>写真はあとからでも追加できます</small></div>`;
  return `<div class="form-section photo-form-section"><div class="form-section-heading"><span>できあがり写真</span><small>${allowMultiple ? "材料と手順のスクリーンショットも選べます" : "任意"}</small></div><div class="editor-photo-preview" data-image-preview>${preview}</div><label class="button button-primary file-picker-label"><span>${recipe.imagePath ? "写真を変更" : "写真を選ぶ"}</span><input name="image" type="file" accept="image/*" ${allowMultiple ? "multiple" : ""}></label><small class="field-help">${allowMultiple ? "Web版では選択した最初の画像を代表画像として保存します。材料・作り方は下の欄で確認してください。" : "iPhone版と同じく、保存時に大きな画像は2048px程度へ縮小します。"}</small></div>`;
}

function recipeModal() {
  const editing = state.editingId ? state.recipes.find((recipe) => recipe.id === state.editingId) : null;
  const recipe = editing ?? newRecipe();
  const mode = editing ? "edit" : state.editorMode;
  const title = editing ? "レシピを編集" : mode === "image" ? "画像からレシピ" : mode === "url" ? "URLから取り込む" : "自分のレシピ";
  return modalShell(title, `
    <form class="editor-form" data-form="recipe" data-id="${attr(editing?.id ?? "")}" data-mode="${mode}">
      ${editorPhotoSection(recipe, mode, Boolean(editing))}
      <div class="form-section"><div class="form-section-heading"><span>基本情報</span><small>RecipeClipper</small></div><label class="field-label">レシピ名 <span class="required">必須</span><input name="title" required value="${attr(recipe.title)}" placeholder="例：いつものチキンカレー" autocomplete="off"></label><label class="field-label">ひとこと<textarea name="summary" data-field="summary" rows="2" placeholder="味や特徴をメモ">${esc(recipe.summary)}</textarea></label><label class="field-label">何人分 <small>任意</small><input name="servings" value="${attr(recipe.servings)}" placeholder="例：2人分" autocomplete="off"></label>${editing ? `<label class="field-label">登録方法<select name="sourceKind">${SOURCE_KINDS.map(([value, label]) => `<option value="${value}" ${recipe.sourceKind === value ? "selected" : ""}>${label}</option>`).join("")}</select></label>` : ""}${!editing && mode === "url" ? `<label class="field-label">元URL <span class="required">必須</span><input name="sourceURL" type="url" required value="${attr(state.urlPrefill?.url ?? "")}" placeholder="https://..." autocomplete="url"></label>` : ""}</div>
      <div class="form-section"><div class="form-section-heading"><span>材料</span><small>改行ごとに1行</small></div><p class="editor-help">入力中は自由に改行・挿入できます。表示時に改行ごとに分かれます。</p><textarea name="ingredients" data-field="ingredients" rows="7" placeholder="玉ねぎ 1/2個\n鶏もも肉 300g">${esc((recipe.ingredients ?? []).join("\n"))}</textarea></div>
      <div class="form-section"><div class="form-section-heading"><span>作り方</span><small>改行ごとに1手順</small></div><p class="editor-help">作り方を自由に入力してください。</p><textarea name="instructions" data-field="instructions" rows="8" placeholder="材料を切る\n鍋で煮る">${esc((recipe.instructions ?? []).join("\n"))}</textarea></div>
      <div class="form-section"><div class="form-section-heading"><span>仕上げ</span><small>タグと自分用メモ</small></div><label class="field-label">タグ <small>カンマまたは改行で区切る</small><input name="tags" value="${attr((recipe.tags ?? []).join(", "))}" placeholder="平日, 鍋" autocomplete="off">${tagEditorSuggestions(recipe)}</label><label class="field-label">自分用メモ<textarea name="notes" data-field="notes" rows="4" placeholder="次回の調整、家族の好みなど">${esc(recipe.notes)}</textarea></label></div>
      ${!editing && mode === "image" ? `<div class="form-section"><div class="form-section-heading"><span>画像の本文（任意）</span><small>文字起こし結果を貼り付け</small></div><textarea name="rawImportedText" data-field="raw" rows="8" placeholder="画像内の材料や作り方を貼り付けてください">${esc(recipe.rawImportedText)}</textarea><p class="editor-help">iPhone版の端末内OCRに相当する欄です。Web版では画像を端末外へ送らず、文字は貼り付けて保存できます。</p></div>` : ""}
      ${!editing && mode === "url" ? `<div class="form-section"><div class="form-section-heading"><span>取得した本文（任意）</span><small>貼り付けて保存できます</small></div><textarea name="rawImportedText" data-field="raw" rows="8" placeholder="外部サイトから本文をコピーして貼り付けてください">${esc(state.urlPrefill?.rawImportedText ?? "")}</textarea><p class="editor-help">URL先を自動取得できない場合の代替欄です。材料と作り方は上の欄で確認・修正してから保存してください。</p></div>` : ""}
      ${editing ? `<div class="form-section preference-grid"><div class="form-section-heading"><span>お気に入り・評価</span><small>いつでも変更できます</small></div><label class="check-label"><input name="isFavorite" type="checkbox" ${recipe.isFavorite ? "checked" : ""}> ♥ お気に入り</label><label class="check-label"><input name="wantsRemake" type="checkbox" ${recipe.wantsRemake ? "checked" : ""}> ↺ また作りたい</label><label class="field-label">評価${ratingControl(recipe.rating, "form", "")}</label></div><div class="form-section"><div class="form-section-heading"><span>出典</span><small>任意</small></div><label class="field-label">元URL<input name="sourceURL" type="url" value="${attr(recipe.sourceURL)}" placeholder="https://..." autocomplete="url"></label>${recipe.rawImportedText ? `<label class="field-label">取得した元本文<textarea name="rawImportedText" data-field="raw" rows="5">${esc(recipe.rawImportedText)}</textarea></label>` : ""}</div>` : ""}
      <div class="form-actions"><button type="button" class="button button-quiet" data-action="close-modal">${editing ? "キャンセル" : "戻る"}</button><button type="submit" class="button button-primary">${editing ? "変更を保存" : "保存"}</button></div>
    </form>`, true, "modal-editor");
}

function cookLogModal() {
  const recipe = state.recipes.find((item) => item.id === state.selectedId);
  const editing = recipe?.cookLogs?.find((log) => log.id === state.editingLogId) ?? null;
  const log = editing ?? { id: "", cookedAt: new Date().toISOString(), memo: "", improvementMemo: "", arrangementMemo: "", rating: 0, imagePath: null };
  return modalShell(editing ? "記録を編集" : "作った記録", `
    <form class="editor-form" data-form="cooklog" data-recipe-id="${attr(recipe?.id ?? "")}" data-log-id="${attr(editing?.id ?? "")}">
      <div class="form-section"><label class="field-label">作った日<input name="cookedAt" type="date" value="${attr(dateInputValue(log.cookedAt))}"></label><label class="field-label">写真（任意）<input name="image" type="file" accept="image/*"><small>${log.imagePath ? "新しい画像を選ぶと差し替えます。" : ""}</small></label><label class="field-label">評価${ratingControl(log.rating, "log-form", "")}</label></div>
      <div class="form-section"><label class="field-label">メモ<textarea name="memo" data-field="cooklog-memo" rows="3" placeholder="おいしくできた">${esc(log.memo)}</textarea></label><label class="field-label">次回改善メモ<textarea name="improvementMemo" data-field="cooklog-improvement" rows="3">${esc(log.improvementMemo)}</textarea></label><label class="field-label">アレンジ内容<textarea name="arrangementMemo" data-field="cooklog-arrangement" rows="3">${esc(log.arrangementMemo)}</textarea></label></div>
      <div class="form-actions"><button type="button" class="button button-quiet" data-action="close-modal">キャンセル</button><button type="submit" class="button button-primary">保存</button></div>
    </form>`, false);
}

function newRecipe() {
  const now = new Date().toISOString();
  return {
    id: newUUID(), title: "", summary: "", sourceURL: "", sourceHost: "", sourceImageURL: null, imagePath: null,
    notes: "", tags: [], servings: "", ingredients: [], instructions: [], checkedIngredients: [], normalizedSourceURL: "", sourceKind: "original",
    isFavorite: false, rating: 0, wantsRemake: false, extractedRawText: "", rawImportedText: "", rawImportedHTML: "", importedTextSource: "none",
    extractionConfidence: 0, extractionWarnings: [], ingredientSource: "none", instructionSource: "none", createdAt: now, updatedAt: now, cookLogs: [],
    _unknownFields: {},
  };
}

function normalizeServings(value) {
  return String(value ?? "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .slice(0, 40);
}

async function prepareImageBlob(file) {
  if (!file) return null;
  const maxPixelLength = 2048;
  try {
    let image;
    if (globalThis.createImageBitmap) {
      try {
        image = await createImageBitmap(file, { imageOrientation: "from-image" });
      } catch {
        image = await createImageBitmap(file);
      }
    } else {
      image = await new Promise((resolve, reject) => {
        const url = URL.createObjectURL(file);
        const element = new Image();
        element.onload = () => {
          URL.revokeObjectURL(url);
          resolve(element);
        };
        element.onerror = () => {
          URL.revokeObjectURL(url);
          reject(new Error("画像を読み込めませんでした。"));
        };
        element.src = url;
      });
    }
    const width = image.width;
    const height = image.height;
    const scale = Math.min(1, maxPixelLength / Math.max(width, height));
    if (scale === 1) {
      image.close?.();
      return file;
    }
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(width * scale));
    canvas.height = Math.max(1, Math.round(height * scale));
    const context = canvas.getContext("2d", { alpha: false });
    if (!context) {
      image.close?.();
      return file;
    }
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    image.close?.();
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85));
    return blob ?? file;
  } catch {
    return file;
  }
}

async function storeImageFile(file) {
  const blob = await prepareImageBlob(file);
  const extension = (blob?.type === "image/jpeg"
    ? "jpg"
    : (blob?.type || file.type || "application/octet-stream").split("/").at(-1) || "bin")
    .replace(/[^a-z0-9]/gi, "")
    .toLocaleLowerCase() || "bin";
  const name = `${newUUID()}.${extension}`;
  await putImage(name, blob);
  return name;
}

function scheduleRender() {
  if (renderFrame !== null) return;
  const renderLater = () => {
    renderFrame = null;
    render();
    if (!pendingSearchSelection) return;
    const selection = pendingSearchSelection;
    pendingSearchSelection = null;
    const search = document.querySelector("[data-role=search]");
    if (search) {
      search.focus({ preventScroll: true });
      search.setSelectionRange(selection.start, selection.end);
    }
  };
  if (globalThis.requestAnimationFrame) renderFrame = requestAnimationFrame(renderLater);
  else renderFrame = setTimeout(renderLater, 0);
}

function render() {
  if (!app) return;
  const previousDetailState = Boolean(state.selectedId);
  const previousScrollY = window.scrollY;
  if (pendingImagePreviewURL) {
    URL.revokeObjectURL(pendingImagePreviewURL);
    pendingImagePreviewURL = null;
  }
  const detail = state.selectedId ? state.recipes.find((recipe) => recipe.id === state.selectedId) : null;
  app.innerHTML = state.printPayload
    ? printView(state.printPayload)
    : state.achievementPage === "achievements"
      ? achievementsView()
      : state.achievementPage === "titles"
        ? titlesView()
        : detail
          ? detailView(detail)
          : listView();
  document.body.classList.toggle("modal-is-open", Boolean(state.modal));
  hydrateImages();
  if (state.modal === "settings" && !state.diagnostics) loadDiagnostics();
  if (!state.modal && previousDetailState === Boolean(state.selectedId)) window.scrollTo(0, previousScrollY);
}

function showImagePreview(file) {
  const preview = document.querySelector("[data-image-preview]");
  if (!preview) return;
  if (pendingImagePreviewURL) URL.revokeObjectURL(pendingImagePreviewURL);
  if (!file) {
    pendingImagePreviewURL = null;
    return;
  }
  pendingImagePreviewURL = URL.createObjectURL(file);
  preview.innerHTML = `<img class="editor-photo-image" src="${attr(pendingImagePreviewURL)}" alt="選択した写真のプレビュー">`;
}

async function hydrateImages() {
  const nodes = [...document.querySelectorAll("[data-image]")];
  await Promise.all(nodes.map(async (node) => {
    const fileName = node.dataset.image;
    let url = fileName ? imageURLs.get(fileName) : null;
    if (!url && fileName) {
      const record = await getImage(fileName).catch(() => null);
      if (record?.blob) {
        url = URL.createObjectURL(record.blob);
        imageURLs.set(fileName, url);
      }
    }
    if (!url) url = node.dataset.fallback || null;
    if (url && node.isConnected) {
      node.src = url;
      node.addEventListener("error", () => {
        node.replaceWith(Object.assign(document.createElement("div"), { className: "image-placeholder image-failed", innerHTML: "<span>✦</span>" }));
      }, { once: true });
    } else if (fileName && node.isConnected) {
      node.replaceWith(Object.assign(document.createElement("div"), { className: "image-placeholder image-failed", innerHTML: "<span>✦</span>" }));
    }
  }));
}

async function loadDiagnostics() {
  state.diagnostics = await diagnostics().catch(() => null);
  render();
}

function toast(message, kind = "success") {
  state.toast = { message, kind };
  const node = document.querySelector("#toast");
  if (node) {
    node.textContent = message;
    node.className = `toast toast-${kind} toast-visible`;
    setTimeout(() => {
      if (state.toast?.message === message) {
        state.toast = null;
        node.className = "toast";
      }
    }, 3200);
  }
}

function currentRecipe(id) {
  return state.recipes.find((recipe) => recipe.id === id);
}

function updateRecipe(id, updater) {
  const recipe = currentRecipe(id);
  if (!recipe) return null;
  updater(recipe);
  return recipe;
}

async function saveUpdatedRecipe(recipe, touchUpdatedAt = true) {
  if (touchUpdatedAt) recipe.updatedAt = new Date().toISOString();
  await putRecipe(recipe);
  render();
}

async function saveRecipeForm(form) {
  if (state.busy) return;
  const data = new FormData(form);
  state.busy = true;
  form.classList.add("is-saving");
  form.querySelectorAll("button, input, textarea, select").forEach((element) => {
    if (element.type !== "hidden") element.disabled = true;
  });

  const editingId = form.dataset.id || null;
  const existing = editingId ? currentRecipe(editingId) : null;
  const recipe = existing ? { ...existing, cookLogs: [...(existing.cookLogs ?? [])] } : newRecipe();
  try {
    const mode = form.dataset.mode || "manual";
    const title = String(data.get("title") ?? "").trim();
    if (!title) {
      toast("レシピ名を入力してください。", "error");
      return;
    }
    recipe.title = title;
    recipe.summary = String(data.get("summary") ?? "").trim();
    recipe.servings = normalizeServings(data.get("servings"));
    recipe.sourceURL = editingId || mode === "url" ? normalizeURL(data.get("sourceURL")) : "";
    recipe.sourceHost = sourceHost(recipe.sourceURL);
    recipe.normalizedSourceURL = recipe.sourceURL;
    recipe.sourceKind = editingId ? String(data.get("sourceKind") ?? recipe.sourceKind ?? "web") : mode === "image" ? "image" : mode === "url" ? sourceKindFromURL(recipe.sourceURL) : "original";
    recipe.ingredients = normalizeLines(String(data.get("ingredients") ?? "").split(/\r?\n/));
    recipe.instructions = normalizeLines(String(data.get("instructions") ?? "").split(/\r?\n/));
    recipe.checkedIngredients = (recipe.checkedIngredients ?? []).filter((line) => recipe.ingredients.includes(line));
    recipe.tags = normalizeTags(data.get("tags"));
    recipe.notes = String(data.get("notes") ?? "").trim();
    if (editingId) {
      recipe.isFavorite = data.get("isFavorite") === "on";
      recipe.wantsRemake = data.get("wantsRemake") === "on";
      const ratingFromButtons = form.dataset.formRating;
      if (ratingFromButtons !== undefined) recipe.rating = Number(ratingFromButtons);
      if (form.elements.rawImportedText) recipe.rawImportedText = String(data.get("rawImportedText") ?? "").trim();
    } else {
      recipe.isFavorite = false;
      recipe.rating = 0;
      recipe.wantsRemake = false;
      recipe.extractedRawText = "";
      recipe.rawImportedText = "";
      recipe.rawImportedHTML = "";
      recipe.importedTextSource = mode === "url" ? "url" : "manual";
      recipe.extractionConfidence = 0;
      recipe.extractionWarnings = [];
      recipe.ingredientSource = "manual";
      recipe.instructionSource = "manual";
      if (mode === "url" || mode === "image") {
        const pastedText = String(data.get("rawImportedText") ?? "").trim();
        recipe.rawImportedText = pastedText;
        recipe.extractedRawText = pastedText;
        recipe.importedTextSource = pastedText ? "manualPaste" : mode === "url" ? "url" : "none";
        recipe.extractionWarnings = pastedText ? [mode === "url" ? "Web版ではURL先の本文取得ができないため、貼り付けた本文を保存しました。" : "Web版では画像OCRの代わりに、貼り付けた本文を保存しました。"] : [];
      }
    }

    const file = form.elements.image?.files?.[0];
    if (file) recipe.imagePath = await storeImageFile(file);
    if (!editingId) recipe.createdAt = new Date().toISOString();
    recipe.updatedAt = new Date().toISOString();
    recipe._providedFields = new Set([
      "id", "title", "summary", "sourceURL", "sourceHost", "sourceImageURL", "imagePath", "notes", "tags", "servings", "ingredients", "instructions", "checkedIngredients", "normalizedSourceURL", "sourceKind", "isFavorite", "rating", "wantsRemake", "extractedRawText", "rawImportedText", "rawImportedHTML", "importedTextSource", "extractionConfidence", "extractionWarnings", "ingredientSource", "instructionSource", "createdAt", "updatedAt", "cookLogs",
    ]);
    await putRecipe(recipe);
    state.recipes = existing ? state.recipes.map((item) => item.id === recipe.id ? recipe : item) : [recipe, ...state.recipes];
    state.modal = null;
    state.editorMode = "manual";
    state.urlPrefill = null;
    state.editingId = null;
    toast(existing ? "レシピを更新しました。" : "レシピを保存しました。");
    render();
  } catch (error) {
    toast(`レシピを保存できませんでした: ${error.message}`, "error");
  } finally {
    state.busy = false;
    form.classList.remove("is-saving");
    if (form.isConnected) form.querySelectorAll("button, input, textarea, select").forEach((element) => { element.disabled = false; });
  }
}

async function saveCookLogForm(form) {
  const recipe = currentRecipe(form.dataset.recipeId);
  if (!recipe) return;
  const data = new FormData(form);
  const editing = recipe.cookLogs?.find((log) => log.id === form.dataset.logId);
  const log = editing ? { ...editing } : { id: newUUID(), imagePath: null, _unknownFields: {} };
  log.cookedAt = dateFromInput(data.get("cookedAt"));
  log.memo = String(data.get("memo") ?? "").trim();
  log.improvementMemo = String(data.get("improvementMemo") ?? "").trim();
  log.arrangementMemo = String(data.get("arrangementMemo") ?? "").trim();
  const rating = Number(form.dataset.formRating);
  if (Number.isInteger(rating)) log.rating = Math.max(0, Math.min(5, rating));
  const file = form.elements.image?.files?.[0];
  if (file) log.imagePath = await storeImageFile(file);
  log._providedFields = new Set(["id", "cookedAt", "memo", "imagePath", "rating", "improvementMemo", "arrangementMemo"]);
  recipe.cookLogs = editing ? recipe.cookLogs.map((item) => item.id === log.id ? log : item) : [...(recipe.cookLogs ?? []), log];
  recipe.rating = Math.max(recipe.rating ?? 0, log.rating ?? 0);
  recipe.updatedAt = new Date().toISOString();
  await putRecipe(recipe);
  state.modal = null;
  state.editingLogId = null;
  toast(editing ? "作った記録を更新しました。" : "作った記録を追加しました。");
  render();
}

async function exportBackup() {
  state.busy = true;
  render();
  try {
    const entries = [{ name: "backup.json", data: textEncoder.encode(backupJSONString(state.recipes)) }];
    const imageNames = new Set();
    state.recipes.forEach((recipe) => {
      if (recipe.imagePath) imageNames.add(recipe.imagePath);
      recipe.cookLogs?.forEach((log) => log.imagePath && imageNames.add(log.imagePath));
    });
    const missing = [];
    for (const name of imageNames) {
      const record = await getImage(name);
      if (!record?.blob) {
        missing.push(name);
        continue;
      }
      entries.push({ name: `RecipeImages/${name}`, data: new Uint8Array(await record.blob.arrayBuffer()) });
    }
    const zip = createStoreZip(entries);
    download(new Blob([zip], { type: "application/zip" }), `RecipeClipper-Backup-${new Date().toISOString().slice(0, 10)}.zip`);
    toast(missing.length ? `バックアップを書き出しました。画像${missing.length}件は見つかりませんでした。` : "バックアップを書き出しました。");
  } catch (error) {
    toast(`バックアップ作成に失敗しました: ${error.message}`, "error");
  } finally {
    state.busy = false;
    render();
  }
}

function download(blob, fileName) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function imageNameFromEntry(name) {
  const normalized = name.replaceAll("\\", "/");
  if (normalized.startsWith("RecipeImages/")) return normalized.slice("RecipeImages/".length).split("/").at(-1);
  if (normalized.startsWith("images/")) return normalized.slice("images/".length).split("/").at(-1);
  return null;
}

async function inspectBackupFile(file) {
  const bytes = new Uint8Array(await file.arrayBuffer());
  let jsonText;
  let imageEntries = [];
  if (bytes[0] === 0x50 && bytes[1] === 0x4b) {
    const entries = readStoreZip(bytes);
    const backupEntry = entries.find((entry) => entry.name === "backup.json" || entry.name.endsWith("/backup.json"));
    if (!backupEntry) throw new Error("ZIP内にbackup.jsonがありません。");
    jsonText = textDecoder.decode(backupEntry.data);
    imageEntries = entries
      .map((entry) => ({ name: imageNameFromEntry(entry.name), data: entry.data }))
      .filter((entry) => entry.name);
  } else {
    jsonText = textDecoder.decode(bytes);
  }
  let value;
  try {
    value = JSON.parse(jsonText);
  } catch {
    throw new Error("backup.jsonをJSONとして読み取れませんでした。");
  }
  const inspected = inspectBackupJSON(value);
  const payload = inspected.payload;
  const imageNames = new Set(imageEntries.map((entry) => entry.name));
  const summary = backupSummary(payload, imageNames);
  const roundTrip = inspected.issues.length ? { valid: false, differences: inspected.issues } : validateRoundTrip(payload.recipes);
  state.importPreview = {
    payload,
    images: imageEntries.map(({ name, data }) => ({ name, blob: new Blob([data], { type: mimeType(name) }) })),
    errors: inspected.issues,
    warnings: inspected.warnings,
    summary,
    roundTrip,
    fileName: file.name,
  };
  state.modal = "settings";
  state.diagnostics = null;
  render();
}

function mimeType(name) {
  const extension = name.split(".").at(-1)?.toLocaleLowerCase();
  return ({ jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", heic: "image/heic", webp: "image/webp", gif: "image/gif" })[extension] ?? "application/octet-stream";
}

async function restoreImport() {
  const preview = state.importPreview;
  if (!preview || preview.errors?.length || !preview.roundTrip?.valid) return;
  const imageWarning = preview.summary.missingImages.length ? `\n\n画像${preview.summary.missingImages.length}件はZIP内にないため復元できません。` : "";
  if (!window.confirm(`${preview.summary.recipeCount}件のレシピで現在のIndexedDBを上書きします。${imageWarning}\n\n続行しますか？`)) return;
  state.busy = true;
  render();
  try {
    await replaceAllData(preview.payload.recipes, preview.images);
    state.recipes = preview.payload.recipes;
    state.importPreview = null;
    state.modal = null;
    state.selectedId = null;
    state.diagnostics = null;
    toast(`${preview.summary.recipeCount}件のレシピを復元しました。`);
  } catch (error) {
    toast(`復元に失敗しました: ${error.message}`, "error");
  } finally {
    state.busy = false;
    render();
  }
}

async function deleteCurrentRecipe(id) {
  const recipe = currentRecipe(id);
  if (!recipe || !window.confirm(`「${recipe.title || "無題のレシピ"}」を削除しますか？`)) return;
  await deleteRecipe(id);
  state.recipes = state.recipes.filter((item) => item.id !== id);
  state.selectedId = null;
  toast("レシピを削除しました。");
  render();
}

async function deleteCookLog(recipeId, logId) {
  const recipe = currentRecipe(recipeId);
  const log = recipe?.cookLogs?.find((item) => item.id === logId);
  if (!recipe || !log || !window.confirm("この作った記録を削除しますか？")) return;
  recipe.cookLogs = recipe.cookLogs.filter((item) => item.id !== logId);
  recipe.updatedAt = new Date().toISOString();
  await putRecipe(recipe);
  toast("作った記録を削除しました。");
  render();
}

function shareRecipe(recipe) {
  const blocks = [recipe.title];
  if (recipe.summary) blocks.push(`概要:\n${recipe.summary}`);
  if (recipe.ingredients?.length) blocks.push(`${recipe.servings ? `材料（${recipe.servings}）` : "材料"}:\n${recipe.ingredients.map((line) => `・${line}`).join("\n")}`);
  if (recipe.instructions?.length) blocks.push(`作り方:\n${recipe.instructions.map((line, index) => `${index + 1}. ${line}`).join("\n")}`);
  if (recipe.notes) blocks.push(`メモ:\n${recipe.notes}`);
  if (recipe.sourceURL) blocks.push(`元URL:\n${recipe.sourceURL}`);
  const text = blocks.join("\n\n");
  if (navigator.share) navigator.share({ title: recipe.title, text }).catch(() => {});
  else navigator.clipboard?.writeText(text).then(() => toast("レシピ本文をコピーしました。"), () => toast("共有できませんでした。", "error"));
}

function printRecipes(recipes) {
  const printable = Array.isArray(recipes) ? recipes.filter(Boolean) : [];
  if (!printable.length) {
    toast("印刷するレシピがありません。", "error");
    return;
  }
  const finish = () => {
    if (!state.printPayload) return;
    state.printPayload = null;
    render();
  };
  window.addEventListener("afterprint", finish, { once: true });
  state.printPayload = printable;
  state.selectedId = null;
  state.achievementPage = null;
  state.modal = null;
  render();
  setTimeout(() => window.print?.(), 240);
}

async function handleClick(event) {
  const actionTarget = event.target.closest("[data-action]");
  if (!actionTarget) return;
  const action = actionTarget.dataset.action;
  if (action === "close-modal") {
    if (actionTarget.classList.contains("modal-backdrop") && event.target.closest("[data-modal-card]")) return;
    state.modal = null;
    state.importPreview = null;
    state.editingId = null;
    state.editingLogId = null;
    state.editorMode = "manual";
    state.urlPrefill = null;
    render();
    return;
  }
  if (action === "home") { state.selectedId = null; state.achievementPage = null; state.modal = null; render(); return; }
  if (action === "achievements") { state.selectedId = null; state.achievementPage = "achievements"; state.modal = null; render(); return; }
  if (action === "titles") { state.selectedId = null; state.achievementPage = "titles"; state.modal = null; render(); return; }
  if (action === "append-tag") {
    const input = actionTarget.closest("form")?.elements.tags;
    if (input) {
      input.value = normalizeTags(`${input.value},${actionTarget.dataset.tag ?? ""}`).join(", ");
      input.focus();
    }
    return;
  }
  if (action === "equip-title") {
    const titleID = actionTarget.dataset.titleId ?? "";
    const achievements = achievementsFor(state.recipes);
    const milestone = titleMilestones(achievements).find((item) => item.title.id === titleID);
    if (milestone?.isUnlocked) {
      state.selectedTitleID = state.selectedTitleID === titleID ? "" : titleID;
      writeSelectedTitle(state.selectedTitleID);
      render();
    }
    return;
  }
  if (action === "settings") { state.modal = "settings"; state.diagnostics = null; render(); return; }
  if (action === "add-recipe") { state.achievementPage = null; state.modal = "add-method"; state.editingId = null; state.editorMode = "manual"; render(); return; }
  if (action === "choose-add-mode") {
    const mode = actionTarget.dataset.mode;
    if (mode === "url") {
      state.modal = "url-import";
    } else {
      state.modal = "recipe";
      state.editorMode = mode === "image" ? "image" : "manual";
    }
    render();
    return;
  }
  if (action === "edit-recipe") { state.achievementPage = null; state.modal = "recipe"; state.editingId = state.selectedId; render(); return; }
  if (action === "recipe") { state.achievementPage = null; state.selectedId = actionTarget.dataset.id; render(); return; }
  if (action === "filter") { state.filter = actionTarget.dataset.filter; render(); return; }
  if (action === "tag") { state.tag = state.tag === actionTarget.dataset.tag ? null : actionTarget.dataset.tag; render(); return; }
  if (action === "clear-search") { state.query = ""; render(); return; }
  if (action === "reset-filters") { state.query = ""; state.filter = "all"; state.tag = null; render(); return; }
  if (action === "toggle-favorite") { const recipe = updateRecipe(actionTarget.dataset.id, (item) => { item.isFavorite = !item.isFavorite; }); if (recipe) await saveUpdatedRecipe(recipe, false); return; }
  if (action === "toggle-remake") { const recipe = updateRecipe(actionTarget.dataset.id, (item) => { item.wantsRemake = !item.wantsRemake; }); if (recipe) await saveUpdatedRecipe(recipe, false); return; }
  if (action === "set-rating") {
    const id = actionTarget.dataset.id;
    if (id === "form" || id === "log-form") {
      const form = actionTarget.closest("form");
      if (form) { const next = Number(actionTarget.dataset.rating); form.dataset.formRating = String(form.dataset.formRating === String(next) ? 0 : next); renderFormRating(form); }
    } else {
      const recipe = currentRecipe(id);
      const logId = actionTarget.dataset.logId;
      const value = Number(actionTarget.dataset.rating);
      if (logId) { const log = recipe?.cookLogs?.find((item) => item.id === logId); if (log) { log.rating = log.rating === value ? 0 : value; recipe.updatedAt = new Date().toISOString(); await putRecipe(recipe); render(); } }
      else if (recipe) { recipe.rating = recipe.rating === value ? 0 : value; await putRecipe(recipe); render(); }
    }
    return;
  }
  if (action === "toggle-ingredient") { const recipe = currentRecipe(actionTarget.dataset.id); const line = recipe?.ingredients?.[Number(actionTarget.dataset.index)]; if (recipe && line) { const checked = new Set(recipe.checkedIngredients ?? []); checked.has(line) ? checked.delete(line) : checked.add(line); recipe.checkedIngredients = recipe.ingredients.filter((item) => checked.has(item)); await putRecipe(recipe); render(); } return; }
  if (action === "reset-checklist") { const recipe = currentRecipe(actionTarget.dataset.id); if (recipe) { recipe.checkedIngredients = []; await putRecipe(recipe); render(); } return; }
  if (action === "share-recipe") { const recipe = currentRecipe(actionTarget.dataset.id); if (recipe) shareRecipe(recipe); return; }
  if (action === "print-recipe") { const recipe = currentRecipe(actionTarget.dataset.id); if (recipe) printRecipes([recipe]); return; }
  if (action === "print-all") { printRecipes([...state.recipes]); return; }
  if (action === "add-cook-log") { state.selectedId = actionTarget.dataset.id; state.modal = "cooklog"; state.editingLogId = null; render(); return; }
  if (action === "edit-cook-log") { state.selectedId = actionTarget.dataset.id; state.modal = "cooklog"; state.editingLogId = actionTarget.dataset.logId; render(); return; }
  if (action === "delete-cook-log") { await deleteCookLog(actionTarget.dataset.id, actionTarget.dataset.logId); return; }
  if (action === "delete-recipe") { await deleteCurrentRecipe(actionTarget.dataset.id); return; }
  if (action === "export-backup") { await exportBackup(); return; }
  if (action === "choose-backup") { document.querySelector("#backup-file")?.click(); return; }
  if (action === "restore-backup") { await restoreImport(); return; }
  if (action === "discard-import") { state.importPreview = null; render(); return; }
  if (action === "validate-current") { state.validationReport = validateRoundTrip(state.recipes); render(); return; }
}

function renderFormRating(form) {
  const current = Number(form.dataset.formRating ?? 0);
  form.querySelectorAll(".rating-star").forEach((button) => button.classList.toggle("selected", Number(button.dataset.rating) <= current));
}

async function handleSubmit(event) {
  const form = event.target.closest("form[data-form]");
  if (!form) return;
  event.preventDefault();
  if (form.dataset.form === "recipe") await saveRecipeForm(form);
  if (form.dataset.form === "cooklog") await saveCookLogForm(form);
  if (form.dataset.form === "url-import") {
    const url = normalizeURL(new FormData(form).get("sourceURL"));
    if (!url) {
      toast("レシピURLを入力してください。", "error");
      return;
    }
    state.urlPrefill = { url, sourceKind: sourceKindFromURL(url), rawImportedText: String(data.get("rawImportedText") ?? "").trim() };
    state.modal = "recipe";
    state.editorMode = "url";
    render();
  }
}

async function handleChange(event) {
  if (event.target.matches("[data-role=sort]")) {
    state.sort = SORTS.some(([value]) => value === event.target.value) ? event.target.value : "recentlyUpdated";
    try { localStorage.setItem("recipeclipper-sort", state.sort); } catch { /* in-memory fallback */ }
    render();
    return;
  }
  if (event.target.matches("[data-role=theme]")) {
    state.theme = event.target.value;
    applyTheme();
    return;
  }
  if (event.target.id === "backup-file" && event.target.files?.[0]) {
    try { await inspectBackupFile(event.target.files[0]); }
    catch (error) { toast(`バックアップを読み込めませんでした: ${error.message}`, "error"); }
    event.target.value = "";
  }
  if (event.target.matches('form[data-form="recipe"] input[name="image"]')) {
    showImagePreview(event.target.files?.[0]);
  }
}

function handleInput(event) {
  if (!event.target.matches("[data-role=search]")) return;
  state.query = event.target.value;
  pendingSearchSelection = {
    start: event.target.selectionStart ?? state.query.length,
    end: event.target.selectionEnd ?? state.query.length,
  };
  scheduleRender();
}

async function boot() {
  applyTheme();
  try {
    state.recipes = await listRecipes();
    render();
  } catch (error) {
    state.error = `IndexedDBを開けませんでした。プライベートブラウズ設定やストレージ権限を確認してください。 (${error.message})`;
    render();
  }
  if ("serviceWorker" in navigator && ["http:", "https:"].includes(location.protocol)) {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
  }
}

app?.addEventListener("click", handleClick);
app?.addEventListener("submit", handleSubmit);
app?.addEventListener("change", handleChange);
app?.addEventListener("input", handleInput);
const systemThemeMedia = globalThis.matchMedia?.("(prefers-color-scheme: dark)");
systemThemeMedia?.addEventListener?.("change", () => {
  if (state.theme === "system") applyTheme();
});
document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape" || !state.modal || state.busy) return;
  state.modal = null;
  state.importPreview = null;
  state.editingId = null;
  state.editingLogId = null;
  state.editorMode = "manual";
  state.urlPrefill = null;
  render();
});
boot();
