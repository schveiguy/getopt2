# getopt2

This library is an experimental wrapper for dlang's [getopt](https://dlang.org/phobos/std_getopt.html) function.

## usage

To use, simply declare an option structure and then pass it to getopt2, along with the parameters. Configuration options can be attached via UDA that affect each parameter (such as caseSensitive). Other udas exist, I will document them eventually.

## what it does

It's basically a wrapper to getopt, but uses a struct model to define the options instead of requiring the user to specify everything on the call to getopt. The idea is, you have to define places/functions to be called by getopt anyway, why not use the existing names and structure directly?

Udas replace interspersed config options.

Some config options are for the whole call and are specified on the getopt2 call (such as `passThrough`).

Very much a WIP.

## example

The example from the getopt docs:

```d
import std.getopt;

string data = "file.dat";
int length = 24;
bool verbose;
enum Color { no, yes };
Color color;

void main(string[] args)
{
  auto helpInformation = getopt(
    args,
    "length",  &length,    // numeric
    "file",    &data,      // string
    "verbose", &verbose,   // flag
    "color", "Information about this color", &color);    // enum
  ...

  if (helpInformation.helpWanted)
  {
    defaultGetoptPrinter("Some information about the program.",
      helpInformation.options);
  }
}
```

And the equivalent with getopt2:

```d
import schlib.getopt2;
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

void main(string[] args)
{
  auto helpInformation = args.getopt2(opts);
  ...

  if (helpInformation.helpWanted)
  {
    defaultGetoptPrinter("Some information about the program.",
      helpInformation.options);
  }
}
```
