import java.lang {
    JString=String
}
import com.redhat.ceylon.common.config {
    CeylonConfig,
    ConfigFinder
}
import java.io {
    JFile=File
}

"""Loads formatting options from the given profile.
   
   A profile is a file with the name
   
       "format.``profile``"
   
   next to the regular Ceylon config file. It contains
   formatting options in a `formatter` section, like this:
   
       [formatter]
       indentMode = 4 spaces
       braceOnOwnLine = false
   
   If [[inherit]] is [[true]], options from the profile file
   in the current directory take precedence over options
   from the profile file in the user and system-wide configuration
   directories (as per the default Ceylon configuration mechanism);
   otherwise, only the options from the profile file itself are used."""
shared FormattingOptions loadProfile(profile = "default", inherit = true) {
    """The profile name.
       
       The options are loaded from a configuration file with the name
       
           "format.``profile``"
       
       using the normal configuration file lookup mechanism
       (that is, options are inherited from the user and system-wide
       configuration in a file with the same name)."""
    see (`function configProfileName`)
    String profile;
    """Whether to inherit options from the user and system-wide configuration
       or not.
       
       By default, options are inherited; however, certain users (for example,
       an IDE) might want to disable this."""
    Boolean inherit;
    
    value configFinder = ConfigFinder("format.``profile``", "ceylon.format");
    CeylonConfig config;
    if (inherit) {
        config = configFinder.loadDefaultConfig(JFile("."));
    } else {
        config = configFinder.loadFirstConfig(JFile("."));
    }
    if (config.isSectionDefined("formatter")) {
        return parseFormattingOptions {
            for (JString key in assertNonnulls(config.getOptionNames("formatter").array))
                key.string->assertNonempty(config.getOptionValues("formatter.``key``").array.map((JString? s) {
                            assert (exists s);
                            return s.string;
                        }))
        };
    } else {
        return FormattingOptions();
    }
}

"Loads the profile name from the Ceylon configuration
 (key `formattool.profile`)."
see (`function loadProfile`)
shared String? configProfileName()
        => CeylonConfig.get("formattool.profile");

Iterable<T,Absent> assertNonnulls<T,Absent>(Iterable<T?,Absent> it)
        given Absent satisfies Null
        => { for (t in it) t else nothing };
{T+} assertNonempty<T>({T*} it) {
    assert (nonempty seq = it.sequence());
    return seq;
}