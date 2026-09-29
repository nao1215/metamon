// Environment and a call counter for runs_multiplier_test.gleam.

let count = 0;

export function set_env(name, value) {
  globalThis.process.env[name] = value;
  return undefined;
}

export function unset_env(name) {
  delete globalThis.process.env[name];
  return undefined;
}

export function count_reset() {
  count = 0;
  return undefined;
}

export function count_bump() {
  count += 1;
  return undefined;
}

export function count_get() {
  return count;
}
