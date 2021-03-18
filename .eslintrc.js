module.exports = {
  env: {
    browser: true,
    es6: true,
    node: true,
  },
  extends: ['prettier', 'eslint:recommended'],
  plugins: ['prettier'],
  rules: {
    'prettier/prettier': 'error',
    'arrow-body-style': ['error', 'as-needed'],
  },
  parserOptions: {
    ecmaVersion: 2018,
    sourceType: 'module',
  },
};
