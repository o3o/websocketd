module websocketd.checkpoint;

struct Checkpoint {
   string name;
   string condition;
   string code;

   string toDCode(string datasource, string source, string valuename) {
      import std.format : format;

      return format(`
            case "%s":
            if (%s) {
                %s
                __prevState = "__prev_%s";
                goto case;
            } else {
                __dataBySource[%s] = %s;
                __frames[%s] = %s;
                break;
            }
            case "__prev_%s":
        `, name, condition, code, name, source, datasource, source, valuename, name);
   }
}

string CheckpointSetup(T)(string datasource, string valuename, string source, Checkpoint[] checkpoints...) {
   import std.array : join;
   import std.algorithm : map;
   import std.format : format;
   string f = format(`
        static string __prevState = "start";
        static ubyte[][string] __dataBySource;
        static %s[string] __frames;
        if (%s !in __frames) __frames[%s] = %s.init;
        %s %s = __frames[%s];
        if (%s !in __dataBySource) __dataBySource[%s] = [];

        string changeState(string state) {
            return "{ __prevState = \"" ~ state ~ "\"; goto case \"" ~ state ~ "\"; }";
        }

        %s = __dataBySource[%s] ~ %s;

        switch (__prevState) {
        case "__prev_start":
        case "start":
        %s
        default: __prevState = "start"; __dataBySource[%s] = %s;
        }
    `, T.stringof, source, source, T.stringof, T.stringof, valuename, source, source, source, datasource, source,
         datasource, checkpoints.map!(c => c.toDCode(datasource, source, valuename)).join, source, datasource);
    return f;
}
