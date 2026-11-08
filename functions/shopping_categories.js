'use strict';

/**
 * Grocery categories used to sort shopping items, shared by the AI
 * consolidation and the free list of the app.
 *
 * Keep in sync with `lib/features/shopping/data/shopping_category.dart`
 * (same ids, same order) and `liste_categories_courses.json`.
 */
const SHOPPING_CATEGORIES = [
  { id: 'animaux',                  fr: 'Animaux',                    en: 'Pet Supplies'       },
  { id: 'bebe',                     fr: 'Bébé',                       en: 'Baby'               },
  { id: 'boissons',                 fr: 'Boissons',                   en: 'Beverages'          },
  { id: 'boucherie',                fr: 'Boucherie',                  en: 'Meat & Poultry'     },
  { id: 'boulangerie-viennoiserie', fr: 'Boulangerie & Viennoiserie', en: 'Bakery & Pastries'  },
  { id: 'conserves',                fr: 'Conserves',                  en: 'Canned Goods'       },
  { id: 'cremerie',                 fr: 'Crémerie',                   en: 'Dairy'              },
  { id: 'divers',                   fr: 'Divers',                     en: 'Miscellaneous'      },
  { id: 'entretien',                fr: 'Entretien',                  en: 'Household Cleaning' },
  { id: 'epicerie-salee',           fr: 'Épicerie salée',             en: 'Pantry'             },
  { id: 'epicerie-sucree',          fr: 'Épicerie sucrée',            en: 'Baking & Sweets'    },
  { id: 'fruits-et-legumes',        fr: 'Fruits et légumes',          en: 'Fresh Produce'      },
  { id: 'hygiene',                  fr: 'Hygiène',                    en: 'Personal Care'      },
  { id: 'maison',                   fr: 'Maison',                     en: 'Home & Stationery'  },
  { id: 'petit-dejeuner-et-gouter', fr: 'Petit-déjeuner et goûter',   en: 'Breakfast & Snacks' },
  { id: 'poissonnerie',             fr: 'Poissonnerie',               en: 'Fish & Seafood'     },
  { id: 'rayon-frais',              fr: 'Rayon frais',                en: 'Chilled'            },
  { id: 'surgeles',                 fr: 'Surgelés',                   en: 'Frozen'             },
];

const SHOPPING_CATEGORY_IDS = SHOPPING_CATEGORIES.map((c) => c.id);

const SHOPPING_CATEGORY_ID_SET = new Set(SHOPPING_CATEGORY_IDS);

/** The category id when [raw] is a known one, '' otherwise. */
function normalizeShoppingCategoryId(raw) {
  const id = typeof raw === 'string' ? raw.trim() : '';
  return SHOPPING_CATEGORY_ID_SET.has(id) ? id : '';
}

/** Case-, accent- and spacing-insensitive form of an item label. */
function normalizeLabelForMatch(raw) {
  return (typeof raw === 'string' ? raw : '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Gives back to the consolidated lines the category a traveler chose on the
 * free list, whatever the AI answered: a line takes the category of the
 * free-list item bearing the same label, or of a free-list item it merges
 * (`sourceItems`). Lines without such an item keep the AI's category.
 *
 * @param {Array<object>} consolidatedItems - AI output lines.
 * @param {Array<{label:string, categoryId?:string}>} manualShoppingItems - AI input lines of the free list.
 * @returns {Array<object>} The lines, with `categoryId` overridden where needed.
 */
function applyChosenShoppingCategories(consolidatedItems, manualShoppingItems) {
  const chosenByLabel = new Map();
  for (const row of manualShoppingItems || []) {
    const categoryId = normalizeShoppingCategoryId(row && row.categoryId);
    const key = normalizeLabelForMatch(row && row.label);
    if (!categoryId || !key || chosenByLabel.has(key)) continue;
    chosenByLabel.set(key, categoryId);
  }
  if (chosenByLabel.size === 0) return consolidatedItems;

  return (consolidatedItems || []).map((item) => {
    if (!item || typeof item !== 'object') return item;
    const candidates = [item.itemLabel];
    if (Array.isArray(item.sourceItems)) {
      for (const source of item.sourceItems) {
        if (source && source.source === 'manual') {
          candidates.push(source.originalLabel);
        }
      }
    }
    for (const label of candidates) {
      const chosen = chosenByLabel.get(normalizeLabelForMatch(label));
      if (chosen) {
        return chosen === item.categoryId ? item : { ...item, categoryId: chosen };
      }
    }
    return item;
  });
}

module.exports = {
  SHOPPING_CATEGORIES,
  SHOPPING_CATEGORY_IDS,
  normalizeShoppingCategoryId,
  applyChosenShoppingCategories,
};
