'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  SHOPPING_CATEGORIES,
  SHOPPING_CATEGORY_IDS,
  normalizeShoppingCategoryId,
  applyChosenShoppingCategories,
} = require('./shopping_categories');

describe('SHOPPING_CATEGORIES', () => {
  it('matches the reference list of the repository', () => {
    const reference = require('../liste_categories_courses.json').categories;
    assert.deepEqual(SHOPPING_CATEGORIES, reference);
    assert.deepEqual(SHOPPING_CATEGORY_IDS, reference.map((c) => c.id));
  });
});

describe('normalizeShoppingCategoryId', () => {
  it('keeps known ids', () => {
    assert.equal(normalizeShoppingCategoryId(' boissons '), 'boissons');
  });

  it('drops unknown or missing ids', () => {
    assert.equal(normalizeShoppingCategoryId('999'), '');
    assert.equal(normalizeShoppingCategoryId(''), '');
    assert.equal(normalizeShoppingCategoryId(undefined), '');
    assert.equal(normalizeShoppingCategoryId(42), '');
  });
});

describe('applyChosenShoppingCategories', () => {
  it('restores the category chosen on an item with the same label', () => {
    const result = applyChosenShoppingCategories(
      [
        { itemLabel: 'Rhum arrangé', categoryId: 'epicerie-sucree' },
        { itemLabel: 'Éponges', categoryId: 'maison' },
      ],
      [
        { label: 'rhum arrange', categoryId: 'boissons' },
        { label: 'Éponges' },
      ]
    );
    assert.deepEqual(result, [
      { itemLabel: 'Rhum arrangé', categoryId: 'boissons' },
      { itemLabel: 'Éponges', categoryId: 'maison' },
    ]);
  });

  it('uses the free-list lines merged into a consolidated line', () => {
    const result = applyChosenShoppingCategories(
      [
        {
          itemLabel: 'Tomates',
          categoryId: 'fruits-et-legumes',
          sourceItems: [
            { source: 'recipe', originalLabel: 'Tomates' },
            { source: 'manual', originalLabel: 'Tomates cerises' },
          ],
        },
      ],
      [{ label: 'Tomates cerises', categoryId: 'rayon-frais' }]
    );
    assert.equal(result[0].categoryId, 'rayon-frais');
  });

  it('ignores recipe lines and unknown categories', () => {
    const items = [
      {
        itemLabel: 'Lait',
        categoryId: 'cremerie',
        sourceItems: [{ source: 'recipe', originalLabel: 'Sucre' }],
      },
    ];
    const result = applyChosenShoppingCategories(items, [
      { label: 'Sucre', categoryId: 'epicerie-sucree' },
      { label: 'Lait', categoryId: '999' },
    ]);
    assert.deepEqual(result, items);
  });

  it('leaves the list untouched when nothing was categorized', () => {
    const items = [{ itemLabel: 'Pain', categoryId: 'boulangerie-viennoiserie' }];
    assert.equal(applyChosenShoppingCategories(items, [{ label: 'Pain' }]), items);
  });
});
