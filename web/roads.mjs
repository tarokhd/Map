// Road classes and bridge topology come from OSM tiles. Heights are schematic, not surveyed.
const ROAD_CLASSES = ["motorway", "trunk", "primary", "secondary", "tertiary", "minor", "service", "track"];
export const roadFilter = ["in", ["get", "class"], ["literal", ROAD_CLASSES]];
export const roadWidth = ["match", ["get", "class"], "motorway", 9, "trunk", 9, "primary", 8, "secondary", 7, "tertiary", 6, "minor", 5, "service", 3, 2.5];
const streetWidth = (factor = 1, border = 0) => ["interpolate", ["exponential", 2], ["zoom"],
  14, ["+", ["*", roadWidth, .25 * factor], border],
  18, ["+", ["*", roadWidth, 4 * factor], border],
  22, ["+", ["*", roadWidth, 64 * factor], border]];
export function addRoadLayers(map, before) {
  const width = streetWidth();
  const ground = ["all", roadFilter, ["!=", ["get", "brunnel"], "tunnel"]];
  const common = {type: "line", source: "openfreemap", "source-layer": "transportation", minzoom: 14, filter: ground, layout: {"line-join": "round", "line-cap": "round"}};
  map.addLayer({...common, id: "world-road-edge", paint: {"line-color": "#73939f", "line-width": streetWidth(1, 1.5), "line-opacity": 0.7}}, before);
  map.addLayer({...common, id: "world-road-surface", paint: {"line-color": "#344955", "line-width": width}}, before);
  map.addLayer({...common, id: "world-road-markings", minzoom: 17,
    filter: ["all", ground, ["in", ["get", "class"], ["literal", ["motorway", "trunk", "primary", "secondary", "tertiary"]]]],
    paint: {"line-color": "#d8e5e7", "line-width": ["interpolate", ["linear"], ["zoom"], 17, 0.55, 21, 1.5], "line-dasharray": [3, 5], "line-opacity": 0.5}}, before);
  map.addLayer({...common, id: "world-underpass", filter: ["all", roadFilter, ["==", ["get", "brunnel"], "tunnel"]],
    paint: {"line-color": "#8398aa", "line-width": streetWidth(.7, .5), "line-dasharray": [2, 2], "line-opacity": 0.55}}, before);
}
function mercator([lng, lat]) {
  return [(lng + 180) / 360, (1 - Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360)) / Math.PI) / 2];
}
export function bridgeGeometry(features, anchor) {
  const origin = mercator(anchor), scale = 1 / (40075016.686 * Math.cos(anchor[1] * Math.PI / 180));
  const vertices = [], seen = new Set();
  const widths = {motorway: 9, trunk: 9, primary: 8, secondary: 7, tertiary: 6, minor: 5, service: 3, track: 2.5};
  let count = 0;
  const vertex = (p, z, material) => vertices.push(p[0], p[1], z, material);
  function quad(a, b, c, d, z1, z2, material) {
    vertex(a, z1, material); vertex(b, z2, material); vertex(c, z2, material);
    vertex(a, z1, material); vertex(c, z2, material); vertex(d, z1, material);
  }
  for (const f of features) {
    const p = f.properties || {};
    if (p.brunnel !== 'bridge' || !ROAD_CLASSES.includes(p.class)) continue;
    const lines = f.geometry.type === 'LineString' ? [f.geometry.coordinates] : f.geometry.type === 'MultiLineString' ? f.geometry.coordinates : [];
    for (const line of lines) {
      // Tiles can contain the same bridge more than once; never draw duplicate meshes.
      const signature = `${p.layer || 1}:${p.class}:${JSON.stringify(line)}`;
      if (seen.has(signature)) continue;
      seen.add(signature);
      if (++count > 180) break;
      const height = Math.max(1, Math.min(4, Number(p.layer) || 1)) * 6;
      const width = widths[p.class];
      const xy = line.map(ll => {const m = mercator(ll); return [(m[0] - origin[0]) / scale, (m[1] - origin[1]) / scale];});
      for (let i = 1; i < xy.length; i++) {
        const a = xy[i - 1], b = xy[i], length = Math.hypot(b[0] - a[0], b[1] - a[1]);
        if (length < 0.1 || length > 1500) continue;
        const nx = -(b[1] - a[1]) / length, ny = (b[0] - a[0]) / length;
        const offset = (point, w) => [point[0] + nx * w, point[1] + ny * w];
        quad(offset(a, -width/2), offset(b, -width/2), offset(b, width/2), offset(a, width/2), height, height, 0);
        for (const side of [-1, 1]) {
          const edgeA = offset(a, side * width/2), edgeB = offset(b, side * width/2);
          // Vertical deck walls give the overpass depth, rails carry restrained light.
          vertex(edgeA, height - 1, 1); vertex(edgeB, height - 1, 1); vertex(edgeB, height, 1);
          vertex(edgeA, height - 1, 1); vertex(edgeB, height, 1); vertex(edgeA, height, 1);
          quad(offset(a, side * (width/2 - 0.12)), offset(b, side * (width/2 - 0.12)), offset(b, side * (width/2 + 0.12)), offset(a, side * (width/2 + 0.12)), height + 0.8, height + 0.8, 2);
        }
        // Illustrative centre markings; lane counts are deliberately not inferred.
        for (let t = 0; t < length; t += 10) {
          const end = Math.min(length, t + 4);
          const s = [a[0] + (b[0]-a[0])*t/length, a[1] + (b[1]-a[1])*t/length];
          const e = [a[0] + (b[0]-a[0])*end/length, a[1] + (b[1]-a[1])*end/length];
          quad(offset(s, -.08), offset(e, -.08), offset(e, .08), offset(s, .08), height + .04, height + .04, 3);
        }
      }
    }
  }
  return {vertices: new Float32Array(vertices), origin, scale, count: Math.min(count, 180)};
}
const rgb = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i+2), 16) / 255);
export class BridgeLayer {
  id = 'world-bridges-3d'; type = 'custom'; renderingMode = '3d';
  vertices = 0; origin = [0, 0]; scale = 1; dirty = false;
  palette = {road: '#435b68', edge: '#a5d8dc', accent: '#9adfe1'};
  onAdd(map, gl) {
    this.map = map; this.gl = gl;
    const shader = (type, source) => {
      const s = gl.createShader(type); gl.shaderSource(s, source); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {const info=gl.getShaderInfoLog(s);gl.deleteShader(s);throw Error(info);}
      return s;
    };
    const vs = shader(gl.VERTEX_SHADER, '#version 300 es\nin vec4 a_pos; uniform mat4 u_matrix; out float material; void main(){gl_Position=u_matrix*vec4(a_pos.xyz,1.0);material=a_pos.w;}');
    const fs = shader(gl.FRAGMENT_SHADER, '#version 300 es\nprecision highp float; in float material; uniform vec3 u_road; uniform vec3 u_edge; uniform vec3 u_accent; out vec4 color; void main(){vec3 c=material<0.5?u_road:material<1.5?u_road*0.62:material<2.5?u_accent:u_edge;float a=material<0.5?0.80:0.95;color=vec4(c*a,a);}');
    this.program = gl.createProgram(); gl.attachShader(this.program, vs); gl.attachShader(this.program, fs); gl.linkProgram(this.program);
    gl.deleteShader(vs); gl.deleteShader(fs);
    if (!gl.getProgramParameter(this.program, gl.LINK_STATUS)) throw Error(gl.getProgramInfoLog(this.program));
    this.buffer = gl.createBuffer(); this.vao = gl.createVertexArray();
    gl.bindVertexArray(this.vao); gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    const position = gl.getAttribLocation(this.program, 'a_pos'); gl.enableVertexAttribArray(position); gl.vertexAttribPointer(position, 4, gl.FLOAT, false, 16, 0);
    gl.bindVertexArray(null);
    this.uniform = Object.fromEntries(['matrix','road','edge','accent'].map(n=>[n, gl.getUniformLocation(this.program, `u_${n}`)]));
  }
  update(features, anchor) {
    const mesh = bridgeGeometry(features, anchor);
    this.origin = mesh.origin; this.scale = mesh.scale; this.data = mesh.vertices; this.vertices = mesh.vertices.length / 4; this.dirty = true;
    this.map?.triggerRepaint(); return mesh.count;
  }
  render(gl, args) {
    if (!this.vertices || this.map.getZoom() < 14) return;
    // Translate in double precision before uploading, preserving metre detail at street zoom.
    const base = args.defaultProjectionData.mainMatrix, matrix = new Float32Array(16);
    for (let row=0; row<4; row++) {
      for (let col=0; col<3; col++) matrix[col*4+row]=base[col*4+row]*this.scale;
      matrix[12+row]=base[row]*this.origin[0]+base[4+row]*this.origin[1]+base[12+row];
    }
    gl.useProgram(this.program); gl.bindVertexArray(this.vao); gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    if (this.dirty) {gl.bufferData(gl.ARRAY_BUFFER, this.data, gl.STATIC_DRAW);this.dirty=false;}
    gl.uniformMatrix4fv(this.uniform.matrix, false, matrix);
    for (const name of ['road','edge','accent']) gl.uniform3fv(this.uniform[name], rgb(this.palette[name]));
    gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.LEQUAL); gl.depthMask(true);
    gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA); gl.disable(gl.CULL_FACE);
    gl.drawArrays(gl.TRIANGLES, 0, this.vertices); gl.bindVertexArray(null);
  }
  onRemove(map, gl) {gl.deleteBuffer(this.buffer);gl.deleteVertexArray(this.vao);gl.deleteProgram(this.program);}
}
