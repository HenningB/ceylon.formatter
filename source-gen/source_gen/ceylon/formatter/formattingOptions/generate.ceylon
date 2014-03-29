import ceylon.file {
    Writer,
    parsePath,
    File,
    Resource,
    Nil
}

shared void generate() {
    try (g = Generator()) {
        g.generate();
    }
}

class Generator() satisfies Destroyable {
    
    Writer gitignore;
    Resource gitignoreResource = parsePath("source/ceylon/formatter/options/.gitignore").resource;
    File gitignoreFile;
    if (is Nil gitignoreResource) {
        gitignoreFile = gitignoreResource.createFile();
    } else {
        assert (is File gitignoreResource);
        gitignoreFile = gitignoreResource;
    }
    gitignore = gitignoreFile.Overwriter();
    gitignore.writeLine(".gitignore");
    
    shared void generate() {
        generateFileFormattingOptions();
        generateEnums();
    }
    
    File file(String path) {
        Resource resource = parsePath(path).resource;
        File file;
        if (is Nil resource) {
            file = resource.createFile();
        } else {
            assert (is File resource);
            file = resource;
        }
        gitignore.writeLine(parsePath(path).relativePath("source/ceylon/formatter/options/").string);
        return file;
    }
    
    void generateFileFormattingOptions() {
        try (writer = file("source/ceylon/formatter/options/FormattingOptions_generated.ceylon").Overwriter()) {
            writeHeader(writer);
            writeImports(writer);
            generateSparseFormattingOptions(writer);
            generateFormattingOptions(writer);
            generateCombinedOptions(writer);
            generateVariableOptions(writer);
            generateFormattingFile(writer);
        }
    }
    
    void generateEnums() {
        for (Enum enum in enums) {
            generateFileEnum(enum);
        }
    }
    
    void generateFileEnum(Enum enum) {
        try (writer = file("source/ceylon/formatter/options/``enum.classname``.ceylon").Overwriter()) {
            writeHeader(writer);
            generateEnumClass(writer, enum);
            for (String instance in enum.instances) {
                generateEnumInstance(writer, enum.classname, instance);
            }
        }
    }
    
    void writeHeader(Writer writer) {
        writer.write(
            "/*
              * DO NOT MODIFY THIS FILE
              *
              * It is generated by the source_gen.ceylon.formatter module (folder source-gen),
              * specifically the formattingOptions package therein.
              */
             
             ");
    }
    
    void writeImports(Writer writer) {
        // no imports
    }
    
    void generateSparseFormattingOptions(Writer writer) {
        writer.write(
            "\"A superclass of [[FormattingOptions]] where attributes are optional.
              
              The indented use is that users take a \\\"default\\\" `FormattingOptions` object and apply some
              `SparseFormattingOptions` on top of it using [[CombinedOptions]]; this way, they don't have
              to specify every option each time that they need to provide `FormattingOptions` somewhere.\"\n");
        writer.write("shared class SparseFormattingOptions(");
        variable Boolean needsComma = false;
        for (option in formattingOptions) {
            if (needsComma) {
                writer.write(",");
            }
            writer.write("\n        ``option.name`` = null");
            needsComma = true;
        }
        writer.write(") {\n");
        for (option in formattingOptions) {
            String[] lines = [*option.documentation.split { '\n'.equals; groupSeparators = false; }];
            if (lines.size == 0 || option.documentation == "") {
                writer.write("\n");
            }
            else if (lines.size == 1) {
                writer.write("\n    \"\"\"``option.documentation``\"\"\"\n");
            } else {
                assert (exists firstLine = lines.first);
                assert (exists lastLine = lines.last);
                writer.write("\n    \"\"\"``firstLine``\n");
                if (lines.size > 2) {
                    for (String line in lines[1 .. lines.size - 2]) {
                        writer.write("       ``line``\n");
                    }
                }
                writer.write("       ``lastLine``\"\"\"\n");
            }
            writer.write("    shared default ``option.type``? ``option.name``;\n");
        }
        writer.write("}\n\n");
    }
    
    void generateFormattingOptions(Writer writer) {
        writer.write(
            "\"A bundle of options for the formatter that control how the code should be formatted.
             
              The default arguments are modeled after the `ceylon.language` module and the Ceylon SDK.
              You can refine them using named arguments:
              
                  FormattingOptions {
                      indentMode = Tabs(4);
                      // modify some others
                      // keep the rest
                  }\"\n");
        writer.write("shared class FormattingOptions(");
        variable Boolean needsComma = false;
        for (option in formattingOptions) {
            if (needsComma) {
                writer.write(",");
            }
            writer.write("\n        ``option.name`` = ``option.defaultValue``");
            needsComma = true;
        }
        writer.write(") extends SparseFormattingOptions() {\n");
        for (option in formattingOptions) {
            writer.write("\n    shared actual default ``option.type`` ``option.name``;\n");
        }
        writer.write("}\n\n");
    }
    
    void generateCombinedOptions(Writer writer) {
        writer.write(
            "\"A combination of several [[FormattingOptions]], of which some may be [[Sparse|SparseFormattingOptions]].
             
              Each attribute is first searched in each of the [[decoration]] options, in the order of their appearance,
              and, if it isn't present in any of them, the attribute of [[baseOptions]] is used.
              
              In the typical use case, `baseOptions` will be some default options (e.g. `FormattingOptions()`), and 
              `decoration` will be one `SparseFormattingOptions` object created on the fly:
              
                  FormattingVisitor(tokens, writer, CombinedOptions(defaultOptions,
                      SparseFormattingOptions {
                          indentMode = Mixed(Tabs(8), Spaces(4));
                          // ...
                      }));\"\n");
        writer.write("shared class CombinedOptions(FormattingOptions baseOptions, SparseFormattingOptions+ decoration) extends FormattingOptions() {\n");
        for (option in formattingOptions) {
            writer.write("\n    shared actual ``option.type`` ``option.name`` {\n");
            writer.write("        for (options in decoration) {\n");
            writer.write("            if (exists option = options.``option.name``) {\n");
            writer.write("                return option;\n");
            writer.write("            }\n");
            writer.write("        }\n");
            writer.write("        return baseOptions.``option.name``;\n");
            writer.write("    }\n");
        }
        writer.write("}\n\n");
    }
    
    void generateVariableOptions(Writer writer) {
        writer.write(
            "\"A subclass of [[FormattingOptions]] that makes its attributes [[variable]].
              
              For internal use only.\"\n");
        writer.write("class VariableOptions(FormattingOptions baseOptions) extends FormattingOptions() {\n\n");
        for (option in formattingOptions) {
            writer.write("    shared actual variable ``option.type`` ``option.name`` = baseOptions.``option.name``;\n");
        }
        writer.write("}\n\n");
    }
    
    void generateFormattingFile(Writer writer) {
        writer.write(
            "VariableOptions parseFormattingOptions({<String->{String+}>*} entries, FormattingOptions baseOptions) {
                 // read included files
                 variable VariableOptions options = VariableOptions(baseOptions);
                 if(exists includes = entries.find((String->{String+} entry) => entry.key == \"include\")?.item) {
                     for(include in includes) {
                         options = variableFormattingFile(include, options);
                     }
                 }
                 
                 // read other options
                 for (String->{String+} entry in entries.filter((String->{String+} entry) => entry.key != \"include\")) {
                     String optionName = entry.key;
                     String optionValue = entry.item.last;
                         
                     switch (optionName)\n");
        for (FormattingOption option in formattingOptions) {
            writer.write(
                "        case (\"``option.name``\") {\n");
            writer.write("            ");
            for (String type in option.type.split('|'.equals)) {
                if (exists enum = enums.find((Enum elem) => elem.classname == type)) {
                    for (instance in enum.instances) {
                        writer.write(
                            "if (\"``instance``\" == optionValue) {
                                             options.``option.name`` = ``instance``;
                                         } else ");
                    }
                } else if (type.startsWith("{") && type.endsWith("*}")) {
                    String innerType = type[1 : type.size - 3];
                    String parseFunction;
                    if (innerType == "String") {
                        parseFunction = "s";
                    } else {
                        parseFunction = "if (exists v=parse``innerType``(s)) v";
                    }
                    String comprehension =
                            "{ for (s in optionValue.split()) ``parseFunction`` }";
                    writer.write(
                        "if (!``comprehension``.empty) {
                                         options.``option.name`` = ``comprehension``;
                                     } else ");
                } else if (type.startsWith("Range<")) {
                    "Only [[Integer]] ranges allowed for now"
                    assert (type == "Range<Integer>");
                    writer.write(
                        "if (exists option = parseIntegerRange(optionValue)) {
                                         options.``option.name`` = option;
                                     } else ");
                } else {
                    writer.write(
                        "if (exists option = parse``type``(optionValue)) {
                                         options.``option.name`` = option;
                                     } else ");
                }
            }
            writer.write("{
                                          throw Exception(\"Can't parse value '\`\`optionValue\`\`' for option '``option.name``'!\");
                                      }\n");
            writer.write(
                "        }\n");
        }
        writer.write(
            "        else {
                         throw Exception(\"Unknown option '\`\`optionName\`\`'!\");
                     }
                 }
                 
                 return options;
             }");
    }
    
    void generateEnumClass(Writer writer, Enum enum) {
        writer.writeLine("shared abstract class ``enum.classname``() of ``"|".join(enum.instances)`` {}");
        writer.writeLine();
    }
    
    void generateEnumInstance(Writer writer, String classname, String instance) {
        writer.writeLine("shared object ``instance`` extends ``classname``() {}");
    }
    
    shared actual Anything destroy(Throwable? error) => gitignore.destroy(error);
}
