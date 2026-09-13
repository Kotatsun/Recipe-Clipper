const DB_NAME = "recipeclipper-web";
const DB_VERSION = 1;

let dbPromise;

function requestResult(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error("IndexedDB request failed"));
  });
}

function transactionDone(transaction) {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error ?? new Error("IndexedDB transaction failed"));
    transaction.onabort = () => reject(transaction.error ?? new Error("IndexedDB transaction was aborted"));
  });
}

export function openDatabase() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains("recipes")) {
        database.createObjectStore("recipes", { keyPath: "id" });
      }
      if (!database.objectStoreNames.contains("images")) {
        database.createObjectStore("images", { keyPath: "name" });
      }
      if (!database.objectStoreNames.contains("meta")) {
        database.createObjectStore("meta", { keyPath: "key" });
      }
    };
    request.onsuccess = () => {
      const database = request.result;
      database.onversionchange = () => database.close();
      resolve(database);
    };
    request.onerror = () => reject(request.error ?? new Error("Could not open IndexedDB"));
    request.onblocked = () => reject(new Error("IndexedDB is blocked by another open tab"));
  });
  return dbPromise;
}

export async function listRecipes() {
  const database = await openDatabase();
  const transaction = database.transaction("recipes", "readonly");
  const recipes = await requestResult(transaction.objectStore("recipes").getAll());
  return recipes;
}

export async function getRecipe(id) {
  const database = await openDatabase();
  const transaction = database.transaction("recipes", "readonly");
  return requestResult(transaction.objectStore("recipes").get(id));
}

export async function putRecipe(recipe) {
  const database = await openDatabase();
  const transaction = database.transaction("recipes", "readwrite");
  transaction.objectStore("recipes").put(recipe);
  await transactionDone(transaction);
}

export async function deleteRecipe(id) {
  const database = await openDatabase();
  const readTransaction = database.transaction("recipes", "readonly");
  const recipesStore = readTransaction.objectStore("recipes");
  const [existing, allRecipes] = await Promise.all([
    requestResult(recipesStore.get(id)),
    requestResult(recipesStore.getAll()),
  ]);

  const candidates = existing
    ? [existing.imagePath, ...(existing.cookLogs ?? []).map((log) => log.imagePath)]
    : [];
  const referenced = new Set();
  if (existing) {
    allRecipes.forEach((recipe) => {
      if (recipe.id === id) return;
      if (recipe.imagePath) referenced.add(recipe.imagePath);
      recipe.cookLogs?.forEach((log) => {
        if (log.imagePath) referenced.add(log.imagePath);
      });
    });
  }

  const transaction = database.transaction(["recipes", "images"], "readwrite");
  transaction.objectStore("recipes").delete(id);
  const imagesStore = transaction.objectStore("images");
  candidates.filter(Boolean).filter((name) => !referenced.has(name)).forEach((name) => imagesStore.delete(name));
  await transactionDone(transaction);
}

export async function getImage(name) {
  if (!name) return null;
  const database = await openDatabase();
  const transaction = database.transaction("images", "readonly");
  return requestResult(transaction.objectStore("images").get(name));
}

export async function putImage(name, blob) {
  if (!name || !blob) return;
  const database = await openDatabase();
  const transaction = database.transaction("images", "readwrite");
  transaction.objectStore("images").put({ name, blob, updatedAt: new Date().toISOString() });
  await transactionDone(transaction);
}

export async function listImages() {
  const database = await openDatabase();
  const transaction = database.transaction("images", "readonly");
  return requestResult(transaction.objectStore("images").getAll());
}

export async function replaceAllData(recipes, imageEntries = []) {
  const database = await openDatabase();
  const transaction = database.transaction(["recipes", "images"], "readwrite");
  const recipesStore = transaction.objectStore("recipes");
  const imagesStore = transaction.objectStore("images");
  recipesStore.clear();
  imagesStore.clear();
  recipes.forEach((recipe) => recipesStore.put(recipe));
  imageEntries.forEach(({ name, blob }) => {
    if (name && blob) imagesStore.put({ name, blob, updatedAt: new Date().toISOString() });
  });
  await transactionDone(transaction);
}

export async function diagnostics() {
  const [recipes, images] = await Promise.all([listRecipes(), listImages()]);
  return {
    recipeCount: recipes.length,
    cookLogCount: recipes.reduce((sum, recipe) => sum + (recipe.cookLogs?.length ?? 0), 0),
    imageCount: images.length,
    databaseName: DB_NAME,
    databaseVersion: DB_VERSION,
  };
}

export async function clearAllData() {
  const database = await openDatabase();
  const transaction = database.transaction(["recipes", "images", "meta"], "readwrite");
  transaction.objectStore("recipes").clear();
  transaction.objectStore("images").clear();
  transaction.objectStore("meta").clear();
  await transactionDone(transaction);
}
