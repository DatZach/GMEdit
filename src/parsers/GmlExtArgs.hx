package parsers;
import js.RegExp;
import parsers.GmlReader;
import tools.CharCode;
import tools.Dictionary;
import tools.NativeString;
import tools.NativeArray;
import ui.Preferences;
import gml.GmlAPI;

/**
 * Handles conversion from/to #args magic.
 * @author YellowAfterlife
 */
class GmlExtArgs {
	public static var errorText:String;
	
	/** subscript ("" for top) -> argument data; null on error */
	public static var argData:Dictionary<GmlExtArgData>;
	private static inline var rsOpt0 = '\\s*argument_count\\s*>\\s*(\\d+)\\s*';
	private static inline var rsOpt1 = '\\s*argument\\s*\\[\\s*(\\d+)\\s*\\]\\s*';
	private static var rxOpt = new RegExp("^var\\s+(\\w+)\\s*(?:"
		// `var q; if (argument_count > 3) q = argument[3]; else q = `
		+ ';\\s*if\\s\\($rsOpt0\\)\\s*(\\w+)\\s*=$rsOpt1;\\s*else\\s*(\\w+)\\s*='
	+ '|'
		// `var q = argument_count > 3 ? argument[3] : `
		+ '=$rsOpt0\\?\\s*$rsOpt1\\:'
	+ ')\\s*([^;]+);', "g");
	private static var rxHasOpt = new RegExp('(?:\\?|=|,\\s*$)');
	private static var rxHasTail = new RegExp(',\\s*$');
	private static var rxNotMagic = new RegExp('var\\s+\\w+\\s*=\\s*'
		+ 'argument(?:\\s*\\[\\s*\\d+\\s*\\]|\\d+)', 'g');
	private static var argKeywords:Dictionary<Bool> = {
		var out = new Dictionary();
		out.set("argument", true);
		for (i in 0 ... 16) out.set("argument" + i, true);
		out;
	};
	public static function pre(code:String):String {
		var version = GmlAPI.version;
		if (!Preferences.current.argsMagic) return code;
		var q = new GmlReader(code);
		var out = "";
		var start = 0;
		inline function flush(till:Int) {
			out += q.substring(start, till);
		}
		var rxOpt = GmlExtArgs.rxOpt;
		function proc() {
			var args = "#args";
			var argv = false;
			var found = 0;
			var pos:Int;
			var proc_start = q.pos;
			var c:CharCode;
			var s:String;
			//
			pos = q.pos;
			q.skipLine();
			rxOpt.lastIndex = 0;
			var hasReq = !rxOpt.test(q.substring(pos, q.pos));
			q.pos = pos + (hasReq ? 3 : 0);
			// pass 1: required arguments (could do regexp..?)
			if (hasReq) while (q.loop) {
				//
				q.skipSpaces0();
				if (q.eof) return null;
				// match var name:
				pos = q.pos;
				c = q.peek();
				if (!c.isIdent0()) return null;
				q.skipIdent1();
				s = q.substring(pos, q.pos);
				// add to args:
				if (found > 0) args += ",";
				args += " " + s;
				// match `=`:
				q.skipSpaces0();
				if (q.eof || q.peek() != "=".code) return null;
				q.skip();
				// match `argument`:
				q.skipSpaces0();
				if (q.eof || q.peek() != "a".code) return null;
				pos = q.pos;
				q.skipIdent1();
				s = q.substring(pos, q.pos);
				if (s == "argument") { // match `argument[$i]`
					// `[`:
					q.skipSpaces0();
					if (q.eof || q.peek() != "[".code) return null;
					q.skip();
					// `$i`:
					q.skipSpaces0();
					if (q.eof) return null;
					pos = q.pos;
					q.skipIdent1();
					if (q.substring(pos, q.pos) != "" + found) return null;
					// `]`:
					q.skipSpaces0();
					if (q.eof || q.peek() != "]".code) return null;
					q.skip();
					//
					argv = true;
				} else {
					// match argument$i:
					if (s != "argument" + found) return null;
				}
				//
				found += 1;
				//
				q.skipSpaces0();
				if (q.eof) break;
				c = q.peek();
				switch (c) {
					case ",".code: q.skip();
					case ";".code: {
						q.skip();
						q.skipSpaces0();
						// do not allow #args with trailing data
						if (!q.peek().isSpace1()) return null;
						break;
					};
					default: if (c.isIdent0()) break; else return null;
				}
			}
			// pass 2: optional arguments
			var req = found;
			var till = q.pos;
			while (q.loop) {
				q.skipSpaces1();
				pos = q.pos;
				q.skipIdent1();
				s = q.substring(pos, q.pos);
				if (s != "var") { q.pos = till; break; }
				q.skipLine();
				rxOpt.lastIndex = 0;
				var mt = rxOpt.exec(q.substring(pos, q.pos));
				if (mt == null) { q.pos = till; break; }
				q.pos = pos + rxOpt.lastIndex;
				//
				var name = mt[1];
				var fs = "" + found;
				if (mt[2] != null
					? (mt[2] != fs || mt[4] != fs || mt[3] != name || mt[5] != name)
					: (mt[6] != fs || mt[7] != fs)
				) { q.pos = till; break; }
				//
				var val = mt[8];
				if (found > 0) args += ",";
				args += val == "undefined" ? ' ?$name' : ' $name = $val';
				found += 1;
				//
				till = q.pos;
			}
			if (req == found && argv) args += ",";
			//
			{
				var trailEnd = code.indexOf("\n#define", q.pos);
				var trailCode:String;
				if (trailEnd >= 0) {
					trailCode = code.substring(q.pos, trailEnd);
				} else trailCode = code.substring(q.pos);
				rxNotMagic.lastIndex = 0;
				if (rxNotMagic.test(trailCode)) {
					//q.pos = proc_start;
					return null;
				}
			}
			//
			return args;
		}
		//
		var checkArgs = true;
		while (q.loop) {
			var p = q.pos;
			var c = q.read();
			switch (c) {
				case "/".code: switch (q.peek()) {
					case "/".code: q.skipLine();
					case "*".code: q.skip(); q.skipComment();
					default:
				};
				case '"'.code, "'".code, "`".code, "@".code: q.skipStringAuto(c, version);
				case "#".code: if (p == 0 || q.get(p - 1) == "\n".code) {
					if (q.substring(p, p + 7) == "#define") {
						checkArgs = true; 
					}
				};
				default: {
					if (checkArgs && c.isIdent0()) {
						q.skipIdent1();
						var id = q.substring(p, q.pos);
						if (id == "var") {
							var p1 = q.pos;
							q.pos = p;
							var s = proc();
							if (s != null) {
								flush(p);
								out += s;
								start = q.pos;
								checkArgs = false;
							} else {
								// if we don't find #args, revert reading position to var|
								q.pos = p1;
							}
						} else if (argKeywords[id]) {
							// if we find a argument#/argument[#] before #args line, it's not that.
							checkArgs = false;
						}
					}
				};
			}
		}
		flush(q.pos);
		return out;
	}
	public static function post(code:String):Null<String> {
		var version = GmlAPI.version;
		argData = null;
		if (!Preferences.current.argsMagic || code.indexOf("#args") < 0) return code;
		var data = new Dictionary();
		var argNames:Array<String> = [];
		var argTexts:Array<String> = [];
		var curr = { names: argNames, texts: argTexts };
		data.set("", curr);
		//
		var q = new GmlReader(code);
		var row = 0;
		var out = "";
		var start = 0;
		function flush(till:Int) {
			out += q.substring(start, till);
		}
		inline function error(s:String) {
			errorText = '[row $row] #args: ' + s;
			return true;
		}
		function proc() {
			var reqDone = null;
			var found = 0;
			//
			var p = q.pos;
			q.skipLine();
			var line = q.substring(p, q.pos);
			var hasTail = rxHasTail.test(line);
			var hasOpt = hasTail || rxHasOpt.test(line);
			q.pos = p;
			//
			while (q.loop) {
				q.skipSpaces0();
				//
				var val:String, set:String = " = ";
				var docName = "";
				var docText = "";
				if (q.peek() == "?".code) {
					q.skip();
					q.skipSpaces0();
					val = "undefined";
					docName += "?";
				} else val = null;
				//
				p = q.pos;
				q.skipIdent1();
				var name = q.substring(p, q.pos);
				if (name == "") return error("Expected an argument name");
				docName += name;
				//
				p = q.pos;
				q.skipSpaces0();
				if (q.peek() == "=".code) {
					if (val != null) return error('?$name means that default value is undefined, why assign another default value after that');
					q.skip();
					q.skipSpaces0();
					set = q.substring(p, q.pos);
					//
					p = q.pos;
					var depth = 0;
					while (q.loop) {
						var c = q.read();
						switch (c) {
							case "/".code: switch (q.peek()) {
								case "/".code: q.skipLine();
								case "*".code: q.skip(); row += q.skipComment();
								default:
							};
							case '"'.code, "'".code, "`".code, "@".code: {
								row += q.skipStringAuto(c, version);
							}
							case "(".code, "[".code, "{".code: depth += 1;
							case ")".code, "]".code, "}".code: depth -= 1;
							case ",".code: if (depth <= 0) { q.pos -= 1; break; }
							case "\r".code, "\n".code: q.pos -= 1; break;
							default:
						}
					}
					if (depth != 0) return error('Unbalanced expression for value of $name');
					val = q.substring(p, q.pos);
				}
				//
				if (val != null) {
					docText = "= " + val;
					if (reqDone == false) {
						reqDone = true;
						out += ";\r\n";
					}
					if (version.hasTernaryOperator()) {
						out += 'var $name = argument_count > $found'
							+ ' ? argument[$found] : $val;\r\n';
					} else {
						out += 'var $name; if (argument_count > $found)'
							+ ' $name = argument[$found]; else $name = $val;\r\n';
					}
				} else {
					if (reqDone) return error('Can\'t have required arguments after optional arguments.');
					reqDone = false;
					if (found == 0) {
						out += "var ";
					} else if (found > 0) out += ", ";
					out += '$name = argument' + (hasOpt ? '[$found]' : "" + found);
				}
				argNames.push(docName);
				argTexts.push(docText);
				found += 1;
				q.skipSpaces0();
				if (q.loop) switch (q.peek()) {
					case ",".code: {
						q.skip();
						q.skipSpaces0();
						switch (q.peek()) {
							case "\r".code, "\n".code: q.skipLineEnd(); break;
						}
					};
					case "\r".code, "\n".code: q.skipLineEnd(); break;
					default: return error('Expected a comma or end of line after $name');
				}
			}
			if (hasTail) {
				argNames.push("...");
				argTexts.push("");
			}
			if (found > 0 && reqDone == false) out += ";\r\n";
			return false;
		}
		while (q.loop) {
			var p = q.pos;
			var c = q.read();
			switch (c) {
				case "/".code: switch (q.peek()) {
					case "/".code: q.skipLine();
					case "*".code: q.skip(); row += q.skipComment();
					default:
				};
				case '"'.code, "'".code, "`".code, "@".code: row += q.skipStringAuto(c, version);
				case "#".code: {
					if (q.substring(p, p + 5) == "#args") {
						flush(p);
						q.pos += 4;
						if (proc()) return null;
						start = q.pos;
					} else if ((p == 0 || q.get(p - 1) == "\n".code)
						&& q.substring(p, p + 7) == "#define"
					) {
						// context switch
						flush(p);
						start = p;
						q.pos += 6;
						q.skipSpaces0();
						p = q.pos;
						q.skipIdent1();
						//
						argNames = [];
						argTexts = [];
						curr = { names: argNames, texts: argTexts };
						data.set(q.substring(p, q.pos), curr);
						//
						q.skipLine();
					}
				};
			}
		}
		flush(q.pos);
		argData = data;
		return out;
	}
}
typedef GmlExtArgData = {
	names:Array<String>,
	texts:Array<String>,
};
