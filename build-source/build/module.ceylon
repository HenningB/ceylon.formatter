module build "1" {
    shared import ceylon.build.task "1.1.1";
    import ceylon.build.engine "1.1.1";
    import ceylon.build.tasks.ceylon "1.1.1";
    import ceylon.build.tasks.commandline "1.1.1";
    native("jvm") import ceylon.build.tasks.file "1.1.1";
    import ceylon.build.tasks.misc "1.1.1";
    import ceylon.build.tasks.ant "1.1.1";
    native("jvm") import java.base "7";
}
