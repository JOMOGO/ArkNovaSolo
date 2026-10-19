// Runs a Lua file under MoonSharp with the module set Tabletop Simulator exposes
// (https://api.tabletopsimulator.com/lua-in-tabletop-simulator/), so headless tests
// see the same language subset as the game: no require/io/load, Lua 5.2, doubles only.
//
// usage: moonrun [--compile-only] <file.lua>
// exit code: 0 ok, 1 Lua error, 2 usage
using MoonSharp.Interpreter;

static class Program
{
    const CoreModules TtsModules =
        CoreModules.Basic | CoreModules.Bit32 | CoreModules.Coroutine | CoreModules.Dynamic |
        CoreModules.ErrorHandling | CoreModules.GlobalConsts | CoreModules.Math |
        CoreModules.Metatables | CoreModules.OS_Time | CoreModules.String |
        CoreModules.Table | CoreModules.TableIterators;

    static int Main(string[] args)
    {
        bool compileOnly = args.Length == 2 && args[0] == "--compile-only";
        string? path = compileOnly ? args[1] : (args.Length == 1 ? args[0] : null);
        if (path == null)
        {
            Console.Error.WriteLine("usage: moonrun [--compile-only] <file.lua>");
            return 2;
        }
        var script = new Script(TtsModules);
        script.Options.DebugPrint = s => Console.WriteLine(s);
        try
        {
            string code = File.ReadAllText(path);
            if (compileOnly)
            {
                script.LoadString(code, null, Path.GetFileName(path));
                Console.WriteLine("compiled OK: " + path);
            }
            else
            {
                script.DoString(code, null, Path.GetFileName(path));
            }
            return 0;
        }
        catch (InterpreterException e)
        {
            Console.Error.WriteLine(e.DecoratedMessage ?? e.Message);
            return 1;
        }
    }
}
