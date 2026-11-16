const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const source = readFileSync(`${__dirname}/../shared/runtime/native-bridge.js`, 'utf8');

function host() {
  const calls = [], cancellations = [];
  const context = vm.createContext({navigator: {}, AndroidWorld: {
    requestLocation: (...args) => calls.push(args),
    cancelLocation: id => cancellations.push(id),
  }});
  context.window = context;
  vm.runInContext(source, context);
  return {context, calls, cancellations, geo: context.navigator.geolocation};
}

test('native GPS delivers a single fix once, with bounded timeout', () => {
  const {context, calls, geo} = host();
  const fixes = [];
  geo.getCurrentPosition(p => fixes.push(p), null, {timeout: Infinity});
  assert.deepEqual(calls, [['1', true, 60000]]);
  const position = {coords: {latitude: 35.7, longitude: 51.4, accuracy: 8}, timestamp: Date.now()};
  context.__androidLocation(1, position, null);
  context.__androidLocation(1, position, null);
  assert.deepEqual(fixes, [position]);
});

test('watch survives errors and stops delivering after clearWatch', () => {
  const {context, calls, cancellations, geo} = host();
  const fixes = [], errors = [];
  const id = geo.watchPosition(p => fixes.push(p), e => errors.push(e), {timeout: 0.1});
  assert.deepEqual(calls, [['1', false, 1000]]);
  const error = {code: 3, message: 'timeout'};
  context.__androidLocation(id, null, error);
  context.__androidLocation(id, {timestamp: 1}, null);
  context.__androidLocation(id, {timestamp: 2}, null);
  geo.clearWatch(id);
  context.__androidLocation(id, {timestamp: 3}, null);
  assert.deepEqual(errors, [error]);
  assert.deepEqual(fixes, [{timestamp: 1}, {timestamp: 2}]);
  assert.deepEqual(cancellations, ['1']);
});

test('denied one-shot permission reports error without inventing a position', () => {
  const {context, geo} = host();
  const fixes = [], errors = [];
  geo.getCurrentPosition(p => fixes.push(p), e => errors.push(e));
  context.__androidLocation(1, null, {code: 1});
  context.__androidLocation(1, {timestamp: 1}, null);
  assert.equal(fixes.length, 0);
  assert.equal(errors[0].code, 1);
  assert.throws(() => geo.watchPosition(null), /position callback/);
});

test('ordinary browsers keep their existing geolocation', () => {
  const original = {};
  const context = vm.createContext({navigator: {geolocation: original}});
  context.window = context;
  vm.runInContext(source, context);
  assert.equal(context.navigator.geolocation, original);
});

test('iOS forwards GPS through its message handler using the same callbacks', () => {
  const messages = [];
  const context = vm.createContext({navigator: {}, webkit: {messageHandlers: {world: {postMessage: value => messages.push(value)}}}});
  context.window = context;
  vm.runInContext(source, context);
  const fixes = [];
  const id = context.navigator.geolocation.watchPosition(p => fixes.push(p));
  assert.equal(messages[0].action, 'request');
  assert.equal(messages[0].once, false);
  context.__nativeLocation(id, {timestamp: 123}, null);
  assert.deepEqual(fixes, [{timestamp: 123}]);
  context.navigator.geolocation.clearWatch(id);
  assert.equal(messages[1].action, 'cancel');
});
