import ceylon.build.task {
    goal,
    dependsOn
}
import ceylon.build.tasks.ant {
    AntProject,
    Ant,
    registerAntLibrary
}
import ceylon.build.tasks.ceylon {
    compileModule=compile,
    AllVerboseModes,
    CompileVerboseMode,
    runModule,
    testModule=test,
    document
}
import ceylon.build.tasks.file {
    delete,
    createDirectory
}
import ceylon.file {
    parsePath,
    Path,
    Directory,
    Resource,
    File,
    createFileIfNil,
    Nil
}

String fetchProperty(AntProject antProject, String propertyName, String assertionMessage = "Property ``propertyName`` needs to be set.") {
    String? propertyValue = antProject.getProperty(propertyName);
    if (exists propertyValue) {
        return propertyValue;
    } else {
        throw AssertionError(assertionMessage);
    }
}

File findFile(Path path, String globName) {
    assert(is Directory directory = path.resource);
    {File*} files = directory.files(globName);
    "Did not find exactly one file"
    assert(files.size == 1);
    assert(is File file = files.first);
    return file;
}

AntProject initAntProject() {
    AntProject antProject = AntProject();
    antProject.execute(Ant("property", { "file" -> "build.properties" } ));
    String distRootDir = parsePath(fetchProperty(antProject, "dist.root.dir")).normalizedPath.string;
    antProject.loadModuleClasses("ant-contrib:ant-contrib", "1.0b3");
    registerAntLibrary(antProject, "net/sf/antcontrib/antlib.xml");
    File repoindexJar = findFile(parsePath("``distRootDir``/osgi/lib"), "org.osgi.impl.bundle.repoindex.ant-*.jar");
    File distJar = findFile(parsePath("``distRootDir``/osgi/build"), "com.redhat.ceylon.dist_*.jar");
    File distRepoJar = findFile(parsePath("``distRootDir``/osgi/build"), "com.redhat.ceylon.dist_*.jar");
    antProject.loadUrlClasses("file:``repoindexJar``");
    antProject.loadUrlClasses("file:``distJar``");
    antProject.loadUrlClasses("file:``distRepoJar``");
    registerAntLibrary(antProject, "taskdef.properties");
    String ceylonAntLib = parsePath(fetchProperty(antProject, "ceylon.ant.lib")).normalizedPath.string;
    antProject.loadUrlClasses("file:``ceylonAntLib``");
    registerAntLibrary(antProject, "com/redhat/ceylon/ant/antlib.xml");
    antProject.loadModuleClasses("com.redhat.ceylon.model", "1.1.1");
    return antProject;
}

AntProject antProject = initAntProject();

String property(String propertyName, String assertionMessage = "Property ``propertyName`` needs to be set.") => fetchProperty(antProject, propertyName, assertionMessage);

Path getUserHome() {
    String? home;
    if (operatingSystem.name.lowercased.contains("win")) {
        home = process.environmentVariableValue("USERPROFILE");
    } else {
        home = process.environmentVariableValue("HOME");
    }
    assert(exists home);
    return parsePath(home);
}

Path basedir = parsePath(property("basedir"));
Path userHome = getUserHome();

String moduleCeylonFormatterVersion = property("module.ceylon.formatter.version");
Path distRootDir = parsePath(property("dist.root.dir"));
Path distBinDir = parsePath(property("dist.bin.dir"));
Path distRepoDir = parsePath(property("dist.repo.dir"));
Path distLibsDir = parsePath(property("dist.libs.dir"));

{CompileVerboseMode*}|AllVerboseModes verboseModes = [];
Path ceylonExecutable = parsePath("``distBinDir``/ceylon");
Path outRepo = parsePath("modules");

Path osgi = parsePath("``basedir``/osgi");
Path osgiP2Path = parsePath("``osgi``/p2");
Path osgiDist = parsePath("``osgi``/dist");
Path osgiBuild = parsePath("``osgi``/build");
Path osgiDistPlugins = parsePath("``osgiDist``/plugins");

String ceylonRepoDir = "``userHome``/.ceylon/repo";

Path testSources = parsePath("source");

[Path+] reposetRunSource_Gen = [outRepo];
[Path+] reposetCompileSource = [outRepo, *reposetRunSource_Gen];
[Path+] reposetCompileTest = [outRepo];
[Path+] reposetRunTest = [outRepo, *reposetRunSource_Gen];

String moduleSource_Gen = "source_gen.ceylon.formatter";
String moduleSource = "ceylon.formatter";
String moduleTest = "test.ceylon.formatter";

[String+] modulesSource_Gen = [moduleSource_Gen];
[String+] modulesSource = [moduleSource];
[String+] modulesTest = [moduleTest];

{String+} pts({Path+} p) => p.map<String>((Path p) => p.string);

goal("module-set")
void moduleSet() {
    antProject.executeXml(
        """
           <moduleset id="modules.source">
               <module name="ceylon.formatter"/>
           </moduleset>
           <echo message="moduleset modules.source set to ceylon.formatter"/>
        """);}

"Deletes the test-modules and modules directories"
goal ("clean")
shared void clean() {
    antProject.execute(
        Ant("delete", { "dir" -> outRepo.string } , [
            // exclude build car
            Ant("exclude", { "name" -> "**/build-1.car" })
        ] )
    );
    delete(osgiDist);
    delete(osgiBuild);
    delete(parsePath("source/ceylon/formatter/options/.gitignore"));
}

goal ("compile-source-gen")
void compileSourceGen() {
    compileModule {
        modules = modulesSource_Gen;
        sourceDirectories = "source";
        outputRepository = outRepo.string;
        verboseModes = verboseModes;
        encoding = "UTF-8";
        // pack200 = true;
    };
}

goal ("generate-source")
dependsOn (`function compileSourceGen`)
shared void generateSource() {
    runModule {
        moduleName = "source_gen.ceylon.formatter";
        repositories = reposetRunSource_Gen.map<String>((Path p) => p.string);
    };
}

"Compiles the Ceylon Formatter modules without re-generating sources"
goal ("compile-source")
void compileSource() {
    compileModule {
        modules = modulesSource;
        outputRepository = outRepo.string;
        verboseModes = verboseModes;
        encoding = "UTF-8";
        // pack200 = true;
    };
}

"Compiles the Ceylon Formatter module to the 'modules' repository"
goal ("compile")
dependsOn (`function generateSource`, `function compileSource`)
void compile() {
}

"Compiles the test module"
goal ("compile-test")
void compileTest() {
    compileModule {
        modules = modulesTest;
        outputRepository = outRepo.string;
        verboseModes = verboseModes;
        encoding = "UTF-8";
        sourceDirectories = testSources.string;
    };
}

"Runs the compiled test module"
goal ("test")
dependsOn (`function compile`, `function compileTest`)
void test() {
    testModule {
        modules = modulesTest;
        repositories = reposetRunTest.map<String>((Path p) => p.string);
    };
}

"Documents the Formatter module"
goal ("doc")
void doc() {
    document {
        modules = modulesSource;
        includeSourceCode = true;
        // nomtimecheck = true;
        encoding = "UTF-8";
        link = "http://modules.ceylon-lang.org/1/";
    };
}

"Copies the Formatter modules to the user's repository"
goal ("publish")
dependsOn (`function compile`, `function scripts`)
void publish() {
    antProject.execute(
        Ant("copy", { "todir" -> ceylonRepoDir.string, "overwrite" -> "true" } , [
            Ant("fileset", { "dir" -> outRepo.string, "includes" -> "ceylon/formatter/**" })
        ] )
    );
}

goal ("publish-herd")
dependsOn (`function moduleSet`)
void publishHerd() {
    String herdRepo = property("herd.repo", "Please specify a target Herd upload repo url with -Dherd.repo=...");
    String herdUser = property("herd.user", "Please specify a target Herd user name with -Dherd.user=...");
    String herdPass = property("herd.pass", "Please specify a target Herd password with -Dherd.pass=...");
    compileModule {
        modules = modulesSource;
        outputRepository = herdRepo;
        user = herdUser;
        password = herdPass;
        verboseModes = verboseModes;
        encoding = "UTF-8";
    };
    document {
        modules = modulesSource;
        includeSourceCode = true;
        // nomtimecheck = true;
        outputRepository = herdRepo;
        user = herdUser;
        password = herdPass;
        encoding = "UTF-8";
        link = "http://modules.ceylon-lang.org/1/";
    };
    antProject.execute(
        Ant("ceylon-plugin", { "mode" -> "pack", "out" -> herdRepo, "user" -> herdUser, "pass" -> herdPass } , [
            Ant("moduleset", { "refid" -> "modules.source" })
        ] )
    );
}

goal("scripts")
dependsOn (`function moduleSet`)
void scripts() {
    antProject.execute(
        Ant("ceylon-plugin", { "executable" -> ceylonExecutable.normalizedPath.string, "mode" -> "pack" } , [
            Ant("moduleset", { "refid" -> "modules.source" })
        ] )
    );
}

goal("install")
dependsOn (`function publish`, `function moduleSet`)
void install() {
    antProject.execute(
        Ant("ceylon-plugin", { "mode" -> "install", "force" -> "true" } , [
            Ant("moduleset", { "refid" -> "modules.source" })
        ] )
    );
}

void copyModuleArchiveForOsgi(File currentFile) {
    antProject.setProperty("Bundle-SymbolicName", null);
    antProject.setProperty("Bundle-Version", null);
    print(antProject.getProperty("Bundle-SymbolicName"));
    antProject.executeXml("
                           <loadproperties>
                           <zipentry zipfile='``currentFile.string``' name='META-INF/MANIFEST.MF'/>
                           <filterchain>
                           <linecontainsregexp>
                           <regexp pattern='^(Bundle-SymbolicName|Bundle-Version)'/>
                           </linecontainsregexp>
                           <replaceregex pattern='\\s+$' replace=''/>
                           <replaceregex pattern='^\\s+' replace=''/>
                           </filterchain>
                           </loadproperties>
                           ");
    String? bundleSymbolicName = antProject.getProperty("Bundle-SymbolicName");
    String? bundleVersion = antProject.getProperty("Bundle-Version");
    print(antProject.getProperty("Bundle-SymbolicName"));
    if (exists bundleSymbolicName, exists bundleVersion) {
        antProject.execute(
            Ant("copy", { "verbose" -> "true", "file" -> currentFile.string, "tofile" -> "``osgiDistPlugins``/``bundleSymbolicName``_``bundleVersion``.jar", "overwrite" -> "true" } )
        );
    }
}

void walkDirectories(Directory directory, Anything(File) do) {
    directory.files().each((File f) => do(f));
    directory.childDirectories().each((Directory d) => walkDirectories(d, do));
}

goal("osgi-quick")
shared void osgiQuick() {
    createDirectory(osgiDistPlugins.resource);
    Resource outRepoResource = outRepo.resource;
    assert(is Directory outRepoResource);
    walkDirectories(outRepoResource, (File f) => if (f.name.endsWith(".car") && f.name != "build-1.car") then copyModuleArchiveForOsgi(f) else null);
    antProject.execute(
        Ant("makeurl", { "property" -> "rootUrl", "file" -> osgiDist.string } )
    );
    String rootUrl = property("rootUrl");
    antProject.execute(
        Ant("repoindex", { "name" -> "Ceylon Distribution Bundles", "out" -> "``osgiDist``/repository.xml", "compressed" -> "false", "rooturl" -> rootUrl, "verbose" -> "true" } , [
            Ant("fileset", { "dir" -> osgiDistPlugins.string, "includes" -> "*.jar" })
        ] )
    );
}

// Rule to setup a plugins directory with required bundles
goal("osgi-p2-quick")
dependsOn(`function osgiQuick`)
void osgiP2Quick() {
    createDirectory(osgiBuild.resource);
    Resource bundlesInfo = parsePath("``osgiBuild``/bundles.info").resource;
    assert(is File|Nil bundlesInfo);
    createFileIfNil(bundlesInfo);
    antProject.execute(
        Ant("loadfile", { "srcfile" -> "``basedir``/../ceylon-dist/osgi/p2/bundlesToStart", "property" -> "bundlesToStart" } , [
            Ant("filterchain", { }, [
                Ant("striplinebreaks")
            ])
        ] )
    );
    String destinationRepository = osgiDist.normalizedPath.uriString;
    String categoryDefinition = osgiP2Path.normalizedPath.childPath("category.xml").uriString;
    String bundlesInfoUrl = osgiBuild.normalizedPath.childPath("bundles.info").uriString;
    String bundlesToStart = property("bundlesToStart");
    antProject.execute(
        Ant("exec", { "dir" -> basedir.string, "executable" -> "eclipse", "failonerror" -> "true" } , [
            Ant("arg", { "value" -> "-noSplash" }),
            Ant("arg", { "value" -> "-clean" }),
            Ant("arg", { "value" -> "-console" }),
            Ant("arg", { "value" -> "-consolelog" }),
            Ant("arg", { "value" -> "--launcher.suppressErrors" }),
            Ant("arg", { "value" -> "-application" }),
            Ant("arg", { "value" -> "org.eclipse.equinox.p2.publisher.FeaturesAndBundlesPublisher" }),
            Ant("arg", { "value" -> "-metadataRepositoryName" }),
            Ant("arg", { "value" -> "Ceylon SDK Bundles" }),
            Ant("arg", { "value" -> "-metadataRepository" }),
            Ant("arg", { "value" -> destinationRepository }),
            Ant("arg", { "value" -> "-artifactRepositoryName" }),
            Ant("arg", { "value" -> "Ceylon SDK Bundles" }),
            Ant("arg", { "value" -> "-artifactRepository" }),
            Ant("arg", { "value" -> destinationRepository }),
            Ant("arg", { "value" -> "-source" }),
            Ant("arg", { "file" -> osgiDist.normalizedPath.string }),
            Ant("arg", { "value" -> "-publishArtifacts" }),
            Ant("arg", { "value" -> "-append" }),
            Ant("arg", { "value" -> "-vmargs" }),
            Ant("arg", { "value" -> "-Dorg.eclipse.equinox.simpleconfigurator.configUrl=``bundlesInfoUrl``" }),
            Ant("arg", { "value" -> "-Dosgi.bundles=``bundlesToStart``" })
        ] ),
        Ant("exec", { "dir" -> basedir.string, "executable" -> "eclipse" } , [
            Ant("arg", { "value" -> "-noSplash" }),
            Ant("arg", { "value" -> "-clean" }),
            Ant("arg", { "value" -> "-console" }),
            Ant("arg", { "value" -> "-consolelog" }),
            Ant("arg", { "value" -> "--launcher.suppressErrors" }),
            Ant("arg", { "value" -> "-application" }),
            Ant("arg", { "value" -> "org.eclipse.equinox.p2.publisher.CategoryPublisher" }),
            Ant("arg", { "value" -> "-metadataRepository" }),
            Ant("arg", { "value" -> destinationRepository }),
            Ant("arg", { "value" -> "-categoryDefinition" }),
            Ant("arg", { "value" -> categoryDefinition }),
            Ant("arg", { "value" -> "-categoryQualifier" }),
            Ant("arg", { "value" -> "ceylon.sdk" }),
            Ant("arg", { "value" -> "-vmargs" }),
            Ant("arg", { "value" -> "-Dorg.eclipse.equinox.simpleconfigurator.configUrl=``bundlesInfoUrl``" }),
            Ant("arg", { "value" -> "-Dosgi.bundles=``bundlesToStart``" })
        ] )
    );
}

goal("osgi")
dependsOn(`function compile`, `function osgiQuick`)
void osgiGoal() {
}

goal("osgi-p2")
dependsOn(`function compile`, `function osgiP2Quick`)
void osgiP2() {
}

goal("ide")
dependsOn(`function osgiP2`)
void ide() {
}

goal("ide-quick")
dependsOn(`function osgiP2Quick`)
void ideQuick() {
    String archivePath = "``outRepo``/ceylon/formatter/``moduleCeylonFormatterVersion``/ceylon.formatter-``moduleCeylonFormatterVersion``.car";
    antProject.execute(
        Ant("basename", { "file" -> archivePath, "property" -> "archiveFileName" } )
    );
    String archiveFileName = property("archiveFileName");
    String proxyProject = "../ceylon-ide-eclipse/required-bundle-proxies/``archiveFileName``";
    antProject.execute(
        Ant("mkdir", { "dir" -> proxyProject }),
        Ant("delete", { "dir" -> "``proxyProject``/META-INF", "failonerror" -> "false"}),
        Ant("copy", { "todir" -> proxyProject, "overwrite" -> "true" } , [
            Ant("zipfileset", { "src" -> archivePath, "includes" -> "META-INF/**" }),
            Ant("fileset", { "file" -> archivePath })
        ] ),
        Ant("manifest", { "file" -> "``proxyProject``/META-INF/MANIFEST.MF", "mode" -> "update" } , [
            Ant("attribute", { "name" -> "Bundle-Classpath", "value" -> archiveFileName })
        ] )
    );
    
}

"formats the formatter with itself"
goal("format")
dependsOn(`function compile`)
void format() {
    runModule {
        moduleName = "ceylon.formatter";
        repositories = reposetCompileSource.map<String>((Path p) => p.string);
        moduleArguments = [ "source" ];
    };
}

"Publish to repository and IDE"
goal("update")
dependsOn(`function publish`, `function ide`)
void update() {
}
