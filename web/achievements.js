export const ACHIEVEMENT_CATEGORIES = [
  { id: "collection", title: "レシピ蒐集", subtitle: "COLLECTION", symbol: "books.vertical.fill" },
  { id: "cooking", title: "料理の腕前", subtitle: "COOKING", symbol: "flame.fill" },
  { id: "discovery", title: "味の探究", subtitle: "DISCOVERY", symbol: "safari.fill" },
  { id: "journal", title: "台所の記録", subtitle: "JOURNAL", symbol: "pencil.and.scribble" },
];

export const TITLE_STORAGE_KEY = "SelectedKitchenTitleID";

const SOURCE_KINDS = new Set(["instagram", "youtube", "cookpad", "web"]);

const TITLE_DEFINITIONS = {
  prelude: { id: "prelude", name: "台所の旅支度", symbol: "fork.knife", tone: "copper" },
  beginner: { id: "beginner", name: "はじまりの料理人", symbol: "sparkles", tone: "copper" },
  explorer: { id: "explorer", name: "献立の探検家", symbol: "map.fill", tone: "basil" },
  "home-cook": { id: "home-cook", name: "暮らしの料理人", symbol: "frying.pan.fill", tone: "basil" },
  cultivator: { id: "cultivator", name: "味を育てる人", symbol: "leaf.fill", tone: "berry" },
  curator: { id: "curator", name: "食卓のキュレーター", symbol: "star.circle.fill", tone: "berry" },
  artisan: { id: "artisan", name: "百味の料理家", symbol: "medal.fill", tone: "gold" },
  maestro: { id: "maestro", name: "台所のマエストロ", symbol: "trophy.fill", tone: "gold" },
  "golden-cook": { id: "golden-cook", name: "黄金の料理人", symbol: "crown.fill", tone: "gold" },
  legend: { id: "legend", name: "台所の伝説", symbol: "crown.fill", tone: "gold" },
  collector: { id: "collector", name: "レシピ蒐集家", symbol: "books.vertical.fill", tone: "basil" },
  "daily-cook": { id: "daily-cook", name: "日々の料理人", symbol: "flame.fill", tone: "copper" },
  "taste-explorer": { id: "taste-explorer", name: "味覚の探究家", symbol: "safari.fill", tone: "berry" },
  "kitchen-writer": { id: "kitchen-writer", name: "台所の記録家", symbol: "pencil.and.scribble", tone: "basil" },
  "archive-master": { id: "archive-master", name: "料理書庫の館主", symbol: "building.columns.fill", tone: "gold" },
  "flame-master": { id: "flame-master", name: "炎のマエストロ", symbol: "flame.circle.fill", tone: "gold" },
  "taste-navigator": { id: "taste-navigator", name: "味覚の航海士", symbol: "safari.fill", tone: "gold" },
  "chronicle-master": { id: "chronicle-master", name: "食卓の年代記作家", symbol: "text.book.closed.fill", tone: "gold" },
};

const JOURNEY_TARGETS = [
  ["prelude", 0],
  ["beginner", 1],
  ["explorer", 5],
  ["home-cook", 10],
  ["cultivator", 15],
  ["curator", 20],
  ["artisan", 25],
  ["maestro", 30],
  ["golden-cook", 35],
  ["legend", null],
];

const SPECIALIST_TARGETS = {
  collection: 5,
  cooking: 6,
  discovery: 4,
  journal: 4,
};

const SPECIALIST_TITLES = {
  collection: "collector",
  cooking: "daily-cook",
  discovery: "taste-explorer",
  journal: "kitchen-writer",
};

const MASTERY_TITLES = {
  collection: "archive-master",
  cooking: "flame-master",
  discovery: "taste-navigator",
  journal: "chronicle-master",
};

function text(value) {
  return String(value ?? "").trim();
}

function validDate(value) {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

function dateKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function weekKey(date) {
  const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  // Calendar.current on the Japanese iPhone defaults to a Sunday-based week.
  start.setDate(start.getDate() - start.getDay());
  return dateKey(start);
}

function longestWeekStreak(dates) {
  const weekStarts = [...new Set(dates.map(weekKey))].sort();
  if (!weekStarts.length) return 0;
  let longest = 1;
  let current = 1;
  for (let index = 1; index < weekStarts.length; index += 1) {
    const previous = new Date(`${weekStarts[index - 1]}T00:00:00`);
    const currentWeek = new Date(`${weekStarts[index]}T00:00:00`);
    const difference = Math.round((currentWeek - previous) / 86400000);
    if (difference === 7) {
      current += 1;
      longest = Math.max(longest, current);
    } else {
      current = 1;
    }
  }
  return longest;
}

export function achievementSnapshot(recipes = []) {
  const safeRecipes = Array.isArray(recipes) ? recipes : [];
  const cookLogs = safeRecipes.flatMap((recipe) => Array.isArray(recipe.cookLogs) ? recipe.cookLogs : []);
  const cookingDates = cookLogs.map((log) => validDate(log.cookedAt)).filter(Boolean);
  const tags = safeRecipes.flatMap((recipe) => Array.isArray(recipe.tags) ? recipe.tags : [])
    .map((tag) => text(tag).toLocaleLowerCase())
    .filter(Boolean);
  const sourceKindCount = new Set(safeRecipes.map((recipe) => text(recipe.sourceKind)).filter((kind) => SOURCE_KINDS.has(kind))).size;

  return {
    recipeCount: safeRecipes.length,
    cookCount: cookLogs.length,
    cookedRecipeCount: safeRecipes.filter((recipe) => cookLogsFor(recipe).length > 0).length,
    cookingDayCount: new Set(cookingDates.map(dateKey)).size,
    longestCookingWeekStreak: longestWeekStreak(cookingDates),
    favoriteCount: safeRecipes.filter((recipe) => recipe.isFavorite).length,
    photoCount: safeRecipes.filter((recipe) => text(recipe.imagePath)).length,
    cookLogPhotoCount: cookLogs.filter((log) => text(log.imagePath)).length,
    completeRecipeCount: safeRecipes.filter((recipe) =>
      Array.isArray(recipe.ingredients) && recipe.ingredients.length > 0 &&
      Array.isArray(recipe.instructions) && recipe.instructions.length > 0
    ).length,
    recipeNoteCount: safeRecipes.filter((recipe) => text(recipe.notes)).length,
    cookLogMemoCount: cookLogs.filter((log) => [log.memo, log.improvementMemo, log.arrangementMemo].some(text)).length,
    highlyRatedCount: safeRecipes.filter((recipe) => Number(recipe.rating) >= 4).length,
    remakeCount: safeRecipes.filter((recipe) => recipe.wantsRemake).length,
    uniqueTagCount: new Set(tags).size,
    sourceKindCount,
    mostCookedRecipeCount: Math.max(0, ...safeRecipes.map((recipe) => cookLogsFor(recipe).length)),
  };
}

function cookLogsFor(recipe) {
  return Array.isArray(recipe?.cookLogs) ? recipe.cookLogs : [];
}

function definition(id, category, eyebrow, title, detail, symbol, current, target, unit, tone) {
  const capped = Math.min(current, target);
  return {
    id, category, eyebrow, title, detail, symbol, current, target, unit, tone,
    isUnlocked: current >= target,
    progress: Math.min(current / target, 1),
    progressText: `${capped} / ${target}${unit}`,
  };
}

export function achievementsFor(valueOrRecipes = []) {
  const value = Array.isArray(valueOrRecipes) ? achievementSnapshot(valueOrRecipes) : valueOrRecipes;
  const v = value ?? achievementSnapshot([]);
  return [
    definition("first-clip", "collection", "FIRST CLIP", "はじめの一皿", "最初のレシピをクリップ", "bookmark.fill", v.recipeCount, 1, "品", "copper"),
    definition("recipe-shelf", "collection", "COLLECTION I", "小さなレシピ棚", "レシピを10品集める", "books.vertical.fill", v.recipeCount, 10, "品", "basil"),
    definition("recipe-library", "collection", "COLLECTION II", "わたしの料理書庫", "レシピを30品集める", "building.columns.fill", v.recipeCount, 30, "品", "gold"),
    definition("recipe-archive", "collection", "COLLECTION III", "六十皿の景色", "レシピを60品集める", "archivebox.fill", v.recipeCount, 60, "品", "berry"),
    definition("recipe-century", "collection", "GRAND ARCHIVE", "百皿料理帖", "レシピを100品集める", "crown.fill", v.recipeCount, 100, "品", "gold"),
    definition("favorites", "collection", "CURATOR I", "選りすぐり", "お気に入りを5品選ぶ", "heart.fill", v.favoriteCount, 5, "品", "berry"),
    definition("favorites-master", "collection", "CURATOR II", "私撰・名菜二十選", "お気に入りを20品選ぶ", "heart.circle.fill", v.favoriteCount, 20, "品", "gold"),
    definition("photos", "collection", "FOOD MEMORY", "おいしい記憶", "写真つきレシピを10品残す", "camera.fill", v.photoCount, 10, "品", "gold"),
    definition("photo-collection", "collection", "VISUAL ARCHIVE", "写真でめくる料理帖", "写真つきレシピを25品残す", "photo.stack.fill", v.photoCount, 25, "品", "basil"),

    definition("first-cook", "cooking", "FIRST COOK", "キッチン点火", "初めてのCook Logを残す", "flame.fill", v.cookCount, 1, "回", "copper"),
    definition("regular-cook", "cooking", "ROUTINE I", "台所の常連", "料理した記録を10回残す", "frying.pan.fill", v.cookCount, 10, "回", "gold"),
    definition("cook-thirty", "cooking", "ROUTINE II", "日々の料理人", "料理した記録を30回残す", "fork.knife", v.cookCount, 30, "回", "basil"),
    definition("cook-seventy-five", "cooking", "ROUTINE III", "七十五回の食卓", "料理した記録を75回残す", "table.furniture.fill", v.cookCount, 75, "回", "berry"),
    definition("cook-one-fifty", "cooking", "MASTER COOK", "百五十皿の手仕事", "料理した記録を150回残す", "medal.fill", v.cookCount, 150, "回", "gold"),
    definition("cooked-variety-ten", "cooking", "REPERTOIRE I", "十皿のレパートリー", "異なるレシピを10品作る", "square.grid.2x2.fill", v.cookedRecipeCount, 10, "品", "basil"),
    definition("cooked-variety-thirty", "cooking", "REPERTOIRE II", "献立の万華鏡", "異なるレシピを30品作る", "circle.grid.3x3.fill", v.cookedRecipeCount, 30, "品", "gold"),
    definition("signature", "cooking", "SIGNATURE I", "十八番の一皿", "同じレシピを3回作る", "repeat.circle.fill", v.mostCookedRecipeCount, 3, "回", "berry"),
    definition("signature-five", "cooking", "SIGNATURE II", "手になじむレシピ", "同じレシピを5回作る", "hand.thumbsup.fill", v.mostCookedRecipeCount, 5, "回", "basil"),
    definition("signature-ten", "cooking", "SIGNATURE III", "我が家の定番", "同じレシピを10回作る", "house.and.flag.fill", v.mostCookedRecipeCount, 10, "回", "gold"),
    definition("streak-four", "cooking", "MOMENTUM I", "四週つづく台所", "4週連続で料理を記録", "calendar.badge.checkmark", v.longestCookingWeekStreak, 4, "週", "copper"),
    definition("streak-twelve", "cooking", "MOMENTUM II", "季節をつなぐ台所", "12週連続で料理を記録", "calendar.circle.fill", v.longestCookingWeekStreak, 12, "週", "gold"),
    definition("cooking-days-thirty", "cooking", "KITCHEN DAYS I", "三十日の手仕事", "30日分の料理を記録", "sun.max.fill", v.cookingDayCount, 30, "日", "basil"),
    definition("cooking-days-hundred", "cooking", "KITCHEN DAYS II", "百日の台所", "100日分の料理を記録", "sparkles", v.cookingDayCount, 100, "日", "gold"),

    definition("sources", "discovery", "EXPLORER I", "レシピ旅人", "3種類の入手元から集める", "safari.fill", v.sourceKindCount, 3, "種", "basil"),
    definition("sources-four", "discovery", "EXPLORER II", "四つの航路", "4種類の入手元から集める", "map.fill", v.sourceKindCount, 4, "種", "gold"),
    definition("tags", "discovery", "TAXONOMY I", "味の標本箱", "10種類のタグで整理する", "tag.fill", v.uniqueTagCount, 10, "種", "basil"),
    definition("tags-thirty", "discovery", "TAXONOMY II", "味覚の地図", "30種類のタグで整理する", "tag.circle.fill", v.uniqueTagCount, 30, "種", "berry"),
    definition("rating", "discovery", "TASTEMAKER I", "確かな舌", "星4以上を5品見つける", "star.fill", v.highlyRatedCount, 5, "品", "gold"),
    definition("rating-twenty", "discovery", "TASTEMAKER II", "二十皿の審美眼", "星4以上を20品見つける", "stars", v.highlyRatedCount, 20, "品", "gold"),
    definition("remake", "discovery", "ENCORE", "もう一度、の予感", "また作りたいを5品選ぶ", "bookmark.fill", v.remakeCount, 5, "品", "berry"),
    definition("remake-fifteen", "discovery", "ENCORE II", "再演を待つ食卓", "また作りたいを15品選ぶ", "bookmark.fill", v.remakeCount, 15, "品", "berry"),

    definition("complete-ten", "journal", "RECIPE CRAFT I", "整った十皿", "材料と作り方を10品に残す", "checklist", v.completeRecipeCount, 10, "品", "basil"),
    definition("complete-forty", "journal", "RECIPE CRAFT II", "頼れる料理帖", "材料と作り方を40品に残す", "text.book.closed.fill", v.completeRecipeCount, 40, "品", "gold"),
    definition("recipe-notes", "journal", "MARGINALIA", "余白のひとこと", "レシピメモを10品に残す", "note.text", v.recipeNoteCount, 10, "品", "copper"),
    definition("cook-memos", "journal", "COOK JOURNAL I", "気づきの記録", "Cook Logメモを10回残す", "pencil.line", v.cookLogMemoCount, 10, "回", "basil"),
    definition("cook-memos-forty", "journal", "COOK JOURNAL II", "育てるレシピ", "Cook Logメモを40回残す", "book.closed.fill", v.cookLogMemoCount, 40, "回", "gold"),
    definition("cook-photos", "journal", "FOOD MEMORY I", "おいしい記憶", "Cook Log写真を10枚残す", "camera.fill", v.cookLogPhotoCount, 10, "枚", "berry"),
    definition("cook-photos-forty", "journal", "FOOD MEMORY II", "食卓の写真集", "Cook Log写真を40枚残す", "photo.on.rectangle.angled", v.cookLogPhotoCount, 40, "枚", "gold"),
  ];
}

export function nextAchievement(achievements) {
  return (achievements ?? []).filter((achievement) => !achievement.isUnlocked).reduce((best, candidate) => {
    if (!best) return candidate;
    if (candidate.progress > best.progress) return candidate;
    if (candidate.progress === best.progress && candidate.target < best.target) return candidate;
    return best;
  }, null);
}

function unlockedByCategory(achievements) {
  return Object.fromEntries(ACHIEVEMENT_CATEGORIES.map((category) => [
    category.id,
    achievements.filter((achievement) => achievement.category === category.id && achievement.isUnlocked).length,
  ]));
}

function totalsByCategory(achievements) {
  return Object.fromEntries(ACHIEVEMENT_CATEGORIES.map((category) => [
    category.id,
    achievements.filter((achievement) => achievement.category === category.id).length,
  ]));
}

function title(id) {
  return { ...TITLE_DEFINITIONS[id] };
}

function specialistTitle(category) {
  return title(SPECIALIST_TITLES[category]);
}

function masteryTitle(category) {
  return title(MASTERY_TITLES[category]);
}

export function kitchenTitle(achievements = []) {
  const unlocked = achievements.filter((achievement) => achievement.isUnlocked).length;
  const unlockedCategories = unlockedByCategory(achievements);
  const totals = totalsByCategory(achievements);
  if (achievements.length > 0 && unlocked === achievements.length) return title("legend");

  const completed = ACHIEVEMENT_CATEGORIES.filter((category) => totals[category.id] > 0 && unlockedCategories[category.id] === totals[category.id]);
  if (completed.length) {
    completed.sort((left, right) => totals[right.id] - totals[left.id]);
    return masteryTitle(completed[0].id);
  }

  const ranked = ACHIEVEMENT_CATEGORIES.map((category, index) => ({
    category,
    index,
    unlocked: unlockedCategories[category.id],
    ratio: totals[category.id] ? unlockedCategories[category.id] / totals[category.id] : 0,
  })).sort((left, right) => right.ratio - left.ratio || right.unlocked - left.unlocked || left.index - right.index);
  const specialist = ranked.find((standing) => standing.unlocked >= SPECIALIST_TARGETS[standing.category.id]);
  if (specialist) return specialistTitle(specialist.category.id);

  if (unlocked === 0) return title("prelude");
  if (unlocked <= 4) return title("beginner");
  if (unlocked <= 9) return title("explorer");
  if (unlocked <= 14) return title("home-cook");
  if (unlocked <= 19) return title("cultivator");
  if (unlocked <= 24) return title("curator");
  if (unlocked <= 29) return title("artisan");
  if (unlocked <= 34) return title("maestro");
  return title("golden-cook");
}

export function titleMilestones(achievements = []) {
  const unlocked = achievements.filter((achievement) => achievement.isUnlocked).length;
  const byCategory = unlockedByCategory(achievements);
  const totals = totalsByCategory(achievements);
  const milestones = JOURNEY_TARGETS.map(([id, target]) => ({
    title: title(id),
    group: "journey",
    condition: target === 0 ? "料理の記録を始める" : `勲章を${target ?? achievements.length}個解除する`,
    current: unlocked,
    target: target ?? achievements.length,
  }));
  ACHIEVEMENT_CATEGORIES.forEach((category) => {
    const target = SPECIALIST_TARGETS[category.id];
    milestones.push({
      title: specialistTitle(category.id),
      group: "specialist",
      condition: `「${category.title}」の勲章を${target}個解除する`,
      current: byCategory[category.id],
      target,
    });
  });
  ACHIEVEMENT_CATEGORIES.forEach((category) => {
    milestones.push({
      title: masteryTitle(category.id),
      group: "mastery",
      condition: `「${category.title}」をすべて制覇する`,
      current: byCategory[category.id],
      target: totals[category.id],
    });
  });
  return milestones.map((milestone) => ({
    ...milestone,
    isUnlocked: milestone.target === 0 || milestone.current >= milestone.target,
    progress: milestone.target > 0 ? Math.min(milestone.current / milestone.target, 1) : 1,
    progressText: milestone.target > 0 ? `${Math.min(milestone.current, milestone.target)} / ${milestone.target}` : "最初から解禁",
  }));
}

export function readSelectedTitle() {
  try {
    return localStorage.getItem(TITLE_STORAGE_KEY) ?? "";
  } catch {
    return "";
  }
}

export function writeSelectedTitle(id) {
  try {
    if (id) localStorage.setItem(TITLE_STORAGE_KEY, id);
    else localStorage.removeItem(TITLE_STORAGE_KEY);
  } catch {
    // Keep the title in memory when localStorage is unavailable.
  }
}

export function equippedTitle(achievements = [], selectedTitleID = "") {
  const selected = titleMilestones(achievements).find((milestone) => milestone.title.id === selectedTitleID && milestone.isUnlocked);
  return selected?.title ?? kitchenTitle(achievements);
}

export function achievementProgress(achievements = []) {
  const unlocked = achievements.filter((achievement) => achievement.isUnlocked).length;
  return { unlocked, total: achievements.length, ratio: achievements.length ? unlocked / achievements.length : 0 };
}

