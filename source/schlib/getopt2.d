module schlib.getopt2;
import std.getopt;
import std.meta;

enum isConfigOption(T) = is(T == std.getopt.config);

// a wrapper for getopt which uses a model instead of a mix of strings/parameters to process command line arguments

@safe GetoptResult getopt2(T, CfgOpts...)(ref string[] args, ref T opts, CfgOpts configopts) if (allSatisfy!(isConfigOption, CfgOpts))
{
    // validate the config options are not argument-based
    foreach(opt; configopts)
    {
        import std.conv : to;
        with(std.getopt.config) switch(opt) {
        case bundling:
        case noBundling:
        case caseSensitive:
        case caseInsensitive:
        case required:
            throw new GetOptException("parameter-specific option " ~ opt.to!string ~ " cannot be passed as config options to getopt2. Use as a uda instead.");
        default: break;
        }
    }
    static string buildGetoptCall() {
        assert(__ctfe);
        static struct memberTraits {
            string name;
            string shortname;
            string description;
            bool required;
            bool bundling;
            bool caseSensitive;
            bool incremental;
        }

        memberTraits getMemberTraits(string n)() {
            memberTraits result;
            result.name = n;
            static foreach(att; __traits(getAttributes, __traits(getMember, T, n)))
            {
                static if(is(typeof(att) == description))
                    result.description = att.desc;
                static if(is(typeof(att) == optname))
                    result.name = att.n;
                static if(is(typeof(att) == shortname))
                    result.shortname = att.sn;
                static if(is(att == incremental))
                    result.incremental = true;
                static if(is(typeof(att) == std.getopt.config)) {
                    if(att == std.getopt.config.caseSensitive)
                        result.caseSensitive = true;
                    else if(att == std.getopt.config.required)
                        result.required = true;
                    else if(att == std.getopt.config.bundling)
                        result.bundling = true;
                }
            }
            return result;
        }
        // keep track of option-spanning configuration options
        bool cfg_caseSensitive = false;
        bool cfg_bundling = false;
        // call getopt 
        string call = "return getopt(args,configopts,";
        // introspect each of the T members
        static foreach(m; __traits(allMembers, T)) {
            static if(!is(__traits(getMember, T, m))) {{ // not a type
                auto mt = getMemberTraits!m;
                // handle any configuration changes
                if(mt.caseSensitive != cfg_caseSensitive)
                {
                    if(mt.caseSensitive)
                        call ~= "std.getopt.config.caseSensitive,";
                    else
                        call ~= "std.getopt.config.caseInsensitive,";
                    cfg_caseSensitive = mt.caseSensitive;
                }

                if(mt.bundling != cfg_bundling)
                {
                    if(mt.bundling)
                        call ~= "std.getopt.config.bundling,";
                    else
                        call ~= "std.getopt.config.noBundling,";
                    cfg_bundling = mt.bundling;
                }
                if(mt.required) {
                    call ~= "std.getopt.config.required,";
                }
                call ~= `"` ~ mt.name;
                if(mt.incremental)
                    call ~= '+';
                if(mt.shortname.length)
                    call ~= `|` ~ mt.shortname;
                call ~= `",`;
                if(mt.description.length)
                    call ~= `"` ~ mt.description ~ `",`;
                static if(is(typeof(__traits(getMember, T, m)) == AliasTo!Args, Args...))
                    call ~= `&opts.` ~ Args[0] ~ `,`;
                else
                    call ~= `&opts.` ~ m ~ `,`;
            }}
        }
        return call ~ ");";
    }

    //pragma(msg, buildGetoptCall());
    mixin(buildGetoptCall());
}

// description of the option
struct description {
    string desc;
}

// alternative name for the option (don't use the member name)
struct optname {
    string n; // can include short name here via "abc|a"
}

// short name for the option
struct shortname {
    string sn;
}

// use to have multiple option setups for the same member
struct AliasTo(string otherMember) {
}

// use to indicate a numeric option is just going to count the number of times
// a name appears in the command line. Equivalent to adding a "+" after the name.
enum incremental;

enum caseSensitive = config.caseSensitive;
enum caseInsensitive = config.caseInsensitive;
enum required = config.required;
enum bundling = config.bundling;
enum noBundling = config.noBundling;

unittest {
    struct Opts {
        int length = 24;
        @caseSensitive
        string data = "file.dat";
        bool verbose;
        enum Color { no, yes }

        @description("Information about this color")
        Color color;
    }

    Opts opts;

    string[] args = ["foo", "--length", "5", "--Verbose", "--color", "yes", "--data", "boo.bah"];
    auto result = args.getopt2(opts);
    assert(opts == Opts(5, "boo.bah", true, Opts.Color.yes));
    defaultGetoptPrinter("foo", result.options);
}

// https://issues.dlang.org/show_bug.cgi?id=17574
@safe unittest
{
    import std.algorithm.searching : startsWith;

    try
    {
        struct Opts {
            @optname("m") string[string] mapping;
        }
        immutable as = arraySep;
        arraySep = ",";
        scope (exit)
            arraySep = as;
        string[] args = ["testProgram", "-m", "a=b,c=\"d,e,f\""];
        Opts opts;
        args.getopt2(opts);
        assert(false, "Exception not thrown");
    }
    catch (GetOptException goe)
        assert(goe.msg.startsWith("Could not find"));
}


// https://issues.dlang.org/show_bug.cgi?id=5316 - arrays with arraySep
@safe unittest
{
    import std.conv;

    arraySep = ",";
    scope (exit) arraySep = "";

    struct Opts {
        @optname("name|n") string[] names;
    }
    Opts opts;
    auto args = ["program.name", "-nfoo,bar,baz"];
    getopt2(args, opts);
    assert(opts.names == ["foo", "bar", "baz"], to!string(opts));

    opts = opts.init;
    args = ["program.name", "-n", "foo,bar,baz"];
    getopt2(args, opts);
    assert(opts.names == ["foo", "bar", "baz"], to!string(opts));

    opts = opts.init;
    args = ["program.name", "--name=foo,bar,baz"];
    getopt2(args, opts);
    assert(opts.names == ["foo", "bar", "baz"], to!string(opts));

    opts = opts.init;
    args = ["program.name", "--name", "foo,bar,baz"];
    getopt2(args, opts);
    assert(opts.names == ["foo", "bar", "baz"], to!string(opts));
}

// https://issues.dlang.org/show_bug.cgi?id=5316 - associative arrays with arraySep
@safe unittest
{
    import std.conv;

    arraySep = ",";
    scope (exit) arraySep = "";

    struct Opts {
        @shortname("v") int[string] values;
    }
    Opts opts;
    auto args = ["program.name", "-vfoo=0,bar=1,baz=2"];
    getopt2(args, opts);
    assert(opts.values == ["foo":0, "bar":1, "baz":2], to!string(opts));

    opts = opts.init;
    args = ["program.name", "-v", "foo=0,bar=1,baz=2"];
    getopt2(args, opts);
    assert(opts.values == ["foo":0, "bar":1, "baz":2], to!string(opts));

    opts = opts.init;
    args = ["program.name", "--values=foo=0,bar=1,baz=2"];
    getopt2(args, opts);
    assert(opts.values == ["foo":0, "bar":1, "baz":2], to!string(opts));

    opts = opts.init;
    args = ["program.name", "--values", "foo=0,bar=1,baz=2"];
    getopt2(args, opts);
    assert(opts.values == ["foo":0, "bar":1, "baz":2], to!string(opts));
}

@safe unittest
{
    import std.conv;
    import std.math.operations : isClose;

    string[] args;
    {
        struct Opts {
            @incremental uint paranoid = 2;
        }
        Opts opts;
        args = ["program.name", "--paranoid", "--paranoid", "--paranoid"];
        getopt2(args, opts);
        assert(opts.paranoid == 5, to!(string)(opts.paranoid));
    }

    {
        enum Color { no, yes }
        struct Opts {
            Color color;
        }
        Opts opts;
        args = ["program.name", "--color=yes",];
        getopt2(args, opts);
        assert(opts.color, to!(string)(opts.color));

        opts.color = Color.no;
        args = ["program.name", "--color", "yes",];
        getopt2(args, opts);
        assert(opts.color, to!(string)(opts.color));
    }

    {
        struct Opts {
            @optname("file") string data = "file.dat";
            int length = 24;
            bool verbose = false;
        }
        Opts opts;
        with(opts) {
            args = ["program.name", "--length=5", "--file", "dat.file", "--verbose"];
            getopt2( args, opts);
            assert(args.length == 1);
            assert(data == "dat.file");
            assert(length == 5);
            assert(verbose);
        }
    }

    {
        struct Opts {
            @optname("output") string[] outputFiles;
        }
        Opts opts;
        with(opts) {
            args = ["program.name", "--output=myfile.txt", "--output", "yourfile.txt"];
            getopt2(args, opts);
            assert(outputFiles.length == 2
                   && outputFiles[0] == "myfile.txt" && outputFiles[1] == "yourfile.txt");

            outputFiles = [];
            arraySep = ",";
            args = ["program.name", "--output", "myfile.txt,yourfile.txt"];
            getopt2(args, opts);
            assert(outputFiles.length == 2
                   && outputFiles[0] == "myfile.txt" && outputFiles[1] == "yourfile.txt");
            arraySep = "";
        }
    }

    foreach (testArgs;
             [["program.name", "--tune=alpha=0.5", "--tune", "beta=0.6"],
             ["program.name", "--tune=alpha=0.5,beta=0.6"],
             ["program.name", "--tune", "alpha=0.5,beta=0.6"]])
    {
        arraySep = ",";
        struct Opts {
            @optname("tune") double[string] tuningParms;
        }
        Opts opts;
        with(opts) {
            getopt2(testArgs, opts);
            assert(testArgs.length == 1);
            assert(tuningParms.length == 2);
            assert(isClose(tuningParms["alpha"], 0.5));
            assert(isClose(tuningParms["beta"], 0.6));
        }
        arraySep = "";
    }

    {
        uint verbosityLevel = 1;
        struct Opts
        {
            @safe:
            static AliasTo!"myHandler" verbose;
            @optname("quiet") void myHandler(string option)
            {
                if (option == "quiet")
                {
                    verbosityLevel = 0;
                }
                else
                {
                    assert(option == "verbose");
                    verbosityLevel = 2;
                }

            }
        }
        Opts opts;
        args = ["program.name", "--quiet"];
        getopt2(args, opts);
        assert(verbosityLevel == 0);
        args = ["program.name", "--verbose"];
        getopt2(args, opts);
        assert(verbosityLevel == 2);

        verbosityLevel = 1;

        struct Opts2
        {
            void verbose(string option, string value)
            {
                assert(option == "verbose");
                verbosityLevel = 2;
            }
        }
        Opts2 opts2;
        args = ["program.name", "--verbose", "2"];
        getopt2(args, opts2);
        assert(verbosityLevel == 2);

        verbosityLevel = 1;
        struct Opts3
        {
            void verbose()
            {
                verbosityLevel = 2;
            }
        }
        Opts3 opts3;
        args = ["program.name", "--verbose"];
        getopt2(args, opts3);
        assert(verbosityLevel == 2);
    }

    {
        struct Opts {
            @caseSensitive:
                bool foo, bar;
        }
        Opts opts;
        with(opts)
        {
            args = ["program.name", "--foo", "--bAr"];
            getopt2(args, opts, std.getopt.config.passThrough);
            assert(opts.foo);
            assert(!opts.bar);
            assert(args[1] == "--bAr");

            // test stopOnFirstNonOption

            args = ["program.name", "--foo", "nonoption", "--bar"];
            opts = opts.init;
            getopt2(args, opts, std.getopt.config.stopOnFirstNonOption);
            assert(foo && !bar && args[1] == "nonoption" && args[2] == "--bar");

            args = ["program.name", "--foo", "nonoption", "--zab"];
            opts = opts.init;
            getopt2(args, opts, std.getopt.config.stopOnFirstNonOption);
            assert(foo && !bar && args[1] == "nonoption" && args[2] == "--zab");

            // test keepEndOfOptions

            args = ["program.name", "--foo", "nonoption", "--bar", "--", "--baz"];
            getopt2(args, opts, std.getopt.config.keepEndOfOptions);
            assert(args == ["program.name", "nonoption", "--", "--baz"]);

            // Ensure old behavior without the keepEndOfOptions

            args = ["program.name", "--foo", "nonoption", "--bar", "--", "--baz"];
            getopt2(args, opts);
            assert(args == ["program.name", "nonoption", "--baz"]);
        }
    }

    {
        args = ["program.name", "--fb1", "--fb2=true", "--tb1=false"];
        struct Opts {
            bool fb1, fb2;
            bool tb1 = true;
        }
        Opts opts;
        getopt2(args, opts);
        with(opts) assert(fb1 && fb2 && !tb1);
    }

    // test function callbacks

    {
        static class MyEx : Exception
        {
            this() { super(""); }
            this(string option) { this(); this.option = option; }
            this(string option, string value) { this(option); this.value = value; }

            string option;
            string value;
        }

        static struct Opts {
            @optname("verbose") static void myStaticHandler1() { throw new MyEx(); }
        }
        Opts opts;
        args = ["program.name", "--verbose"];
        try { getopt2(args, opts); assert(0); }
        catch (MyEx ex) { assert(ex.option is null && ex.value is null); }

        static struct Opts2 {
            @optname("verbose") static void myStaticHandler2(string option) { throw new MyEx(option); }
        }
        Opts2 opts2;
        args = ["program.name", "--verbose"];
        try { getopt2(args, opts2); assert(0); }
        catch (MyEx ex) { assert(ex.option == "verbose" && ex.value is null); }

        static struct Opts3 {
            @optname("verbose") static void myStaticHandler3(string option, string value) { throw new MyEx(option, value); }
        }
        Opts3 opts3;
        args = ["program.name", "--verbose", "2"];
        try { getopt2(args, opts3); assert(0); }
        catch (MyEx ex) { assert(ex.option == "verbose" && ex.value == "2"); }

        // check that GetOptException is thrown if the value is missing
        args = ["program.name", "--verbose"];
        try { getopt2(args, opts3); assert(0); }
        catch (GetOptException e) {}
        catch (Exception e) { assert(0); }
    }
}

/+@safe unittest // @safe std.getopt.config option use
{
    long x = 0;
    string[] args = ["program", "--inc-x", "--inc-x"];
    getopt(args,
           std.getopt.config.caseSensitive,
           "inc-x", "Add one to x", delegate void() { x++; });
    assert(x == 2);
}

// https://issues.dlang.org/show_bug.cgi?id=2142
@safe unittest
{
    bool f_linenum, f_filename;
    string[] args = [ "", "-nl" ];
    getopt
        (
            args,
            std.getopt.config.bundling,
            //std.getopt.config.caseSensitive,
            "linenum|l", &f_linenum,
            "filename|n", &f_filename
        );
    assert(f_linenum);
    assert(f_filename);
}

// https://issues.dlang.org/show_bug.cgi?id=6887
@safe unittest
{
    string[] p;
    string[] args = ["", "-pa"];
    getopt(args, "p", &p);
    assert(p.length == 1);
    assert(p[0] == "a");
}

// https://issues.dlang.org/show_bug.cgi?id=6888
@safe unittest
{
    int[string] foo;
    auto args = ["", "-t", "a=1"];
    getopt(args, "t", &foo);
    assert(foo == ["a":1]);
}

// https://issues.dlang.org/show_bug.cgi?id=9583
@safe unittest
{
    int opt;
    auto args = ["prog", "--opt=123", "--", "--a", "--b", "--c"];
    getopt(args, "opt", &opt);
    assert(args == ["prog", "--a", "--b", "--c"]);
}

@safe unittest
{
    string foo, bar;
    auto args = ["prog", "-thello", "-dbar=baz"];
    getopt(args, "t", &foo, "d", &bar);
    assert(foo == "hello");
    assert(bar == "bar=baz");

    // From https://issues.dlang.org/show_bug.cgi?id=5762
    string a;
    args = ["prog", "-a-0x12"];
    getopt(args, config.bundling, "a|addr", &a);
    assert(a == "-0x12", a);
    args = ["prog", "--addr=-0x12"];
    getopt(args, config.bundling, "a|addr", &a);
    assert(a == "-0x12");

    // From https://issues.dlang.org/show_bug.cgi?id=11764
    args = ["main", "-test"];
    bool opt;
    args.getopt(config.passThrough, "opt", &opt);
    assert(args == ["main", "-test"]);

    // From https://issues.dlang.org/show_bug.cgi?id=15220
    args = ["main", "-o=str"];
    string o;
    args.getopt("o", &o);
    assert(o == "str");

    args = ["main", "-o=str"];
    o = null;
    args.getopt(config.bundling, "o", &o);
    assert(o == "str");
}

// https://issues.dlang.org/show_bug.cgi?id=5228
@safe unittest
{
    import std.conv;
    import std.exception;

    auto args = ["prog", "--foo=bar"];
    int abc;
    assertThrown!GetOptException(getopt(args, "abc", &abc));

    args = ["prog", "--abc=string"];
    assertThrown!ConvException(getopt(args, "abc", &abc));
}

// https://issues.dlang.org/show_bug.cgi?id=7693
@safe unittest
{
    import std.exception;

    enum Foo {
        bar,
        baz
    }

    auto args = ["prog", "--foo=barZZZ"];
    Foo foo;
    assertThrown(getopt(args, "foo", &foo));
    args = ["prog", "--foo=bar"];
    assertNotThrown(getopt(args, "foo", &foo));
    args = ["prog", "--foo", "barZZZ"];
    assertThrown(getopt(args, "foo", &foo));
    args = ["prog", "--foo", "baz"];
    assertNotThrown(getopt(args, "foo", &foo));
}

// Same as https://issues.dlang.org/show_bug.cgi?id=7693 only for `bool`
@safe unittest
{
    import std.exception;

    auto args = ["prog", "--foo=truefoobar"];
    bool foo;
    assertThrown(getopt(args, "foo", &foo));
    args = ["prog", "--foo"];
    getopt(args, "foo", &foo);
    assert(foo);
}

@safe unittest
{
    bool foo;
    auto args = ["prog", "--foo"];
    getopt(args, "foo", &foo);
    assert(foo);
}

@safe unittest
{
    bool foo;
    bool bar;
    auto args = ["prog", "--foo", "-b"];
    getopt(args, config.caseInsensitive,"foo|f", "Some foo", &foo,
        config.caseSensitive, "bar|b", "Some bar", &bar);
    assert(foo);
    assert(bar);
}

@safe unittest
{
    bool foo;
    bool bar;
    auto args = ["prog", "-b", "--foo", "-z"];
    getopt(args, config.caseInsensitive, config.required, "foo|f", "Some foo",
        &foo, config.caseSensitive, "bar|b", "Some bar", &bar,
        config.passThrough);
    assert(foo);
    assert(bar);
}

@safe unittest
{
    import std.exception;

    bool foo;
    bool bar;
    auto args = ["prog", "-b", "-z"];
    assertThrown(getopt(args, config.caseInsensitive, config.required, "foo|f",
        "Some foo", &foo, config.caseSensitive, "bar|b", "Some bar", &bar,
        config.passThrough));
}

@safe unittest
{
    import std.exception;

    bool foo;
    bool bar;
    auto args = ["prog", "--foo", "-z"];
    assertNotThrown(getopt(args, config.caseInsensitive, config.required,
        "foo|f", "Some foo", &foo, config.caseSensitive, "bar|b", "Some bar",
        &bar, config.passThrough));
    assert(foo);
    assert(!bar);
}

@safe unittest
{
    bool foo;
    auto args = ["prog", "-f"];
    auto r = getopt(args, config.caseInsensitive, "help|f", "Some foo", &foo);
    assert(foo);
    assert(!r.helpWanted);
}

@safe unittest // implicit help option without config.passThrough
{
    string[] args = ["program", "--help"];
    auto r = getopt(args);
    assert(r.helpWanted);
}

// std.getopt: implicit help option breaks the next argument
// https://issues.dlang.org/show_bug.cgi?id=13316
@safe unittest
{
    string[] args = ["program", "--help", "--", "something"];
    getopt(args);
    assert(args == ["program", "something"]);

    args = ["program", "--help", "--"];
    getopt(args);
    assert(args == ["program"]);

    bool b;
    args = ["program", "--help", "nonoption", "--option"];
    getopt(args, config.stopOnFirstNonOption, "option", &b);
    assert(args == ["program", "nonoption", "--option"]);
}

// std.getopt: endOfOptions broken when it doesn't look like an option
// https://issues.dlang.org/show_bug.cgi?id=13317
@safe unittest
{
    auto endOfOptionsBackup = endOfOptions;
    scope(exit) endOfOptions = endOfOptionsBackup;
    endOfOptions = "endofoptions";
    string[] args = ["program", "endofoptions", "--option"];
    bool b = false;
    getopt(args, "option", &b);
    assert(!b);
    assert(args == ["program", "--option"]);
}

// make std.getopt ready for DIP 1000
// https://issues.dlang.org/show_bug.cgi?id=20480
@safe unittest
{
    string[] args = ["test", "--foo", "42", "--bar", "BAR"];
    int foo;
    string bar;
    getopt(args, "foo", &foo, "bar", "bar help", &bar);
    assert(foo == 42);
    assert(bar == "BAR");
}
+/

unittest
{
    static int x;
    string[] args = ["progname", "--y", "5"];
    struct Opts
    {
        alias y = x;
    }
    Opts opts;
    getopt2(args, opts);
    assert(x == 5);
}
