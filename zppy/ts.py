import os
import pprint
import re

import jinja2

from zppy.utils import checkStatus, getComponent, getTasks, getYears, submitScript


# -----------------------------------------------------------------------------
def ts(config, scriptDir):

    # --- Initialize jinja2 template engine ---
    templateLoader = jinja2.FileSystemLoader(
        searchpath=config["default"]["templateDir"]
    )
    templateEnv = jinja2.Environment(loader=templateLoader)
    template = templateEnv.get_template("ts.bash")

    # --- List of tasks ---
    tasks = getTasks(config, "ts")
    if len(tasks) == 0:
        return

    # --- Generate and submit ts scripts ---
    for c in tasks:

        # Grid name (if not explicitly defined)
        #   'native' if no remapping
        #   or extracted from mapping filename
        if c["grid"] == "":
            if c["mapping_file"] == "":
                c["grid"] = "native"
            elif c["mapping_file"] == "glb":
                c["grid"] = "glb"
            else:
                tmp = os.path.basename(c["mapping_file"])
                # FIXME: W605 invalid escape sequence '\.'
                tmp = re.sub("\.[^.]*\.nc$", "", tmp)  # noqa: W605
                tmp = tmp.split("_")
                if tmp[0] == "map":
                    c["grid"] = "%s_%s" % (tmp[-2], tmp[-1])
                else:
                    raise Exception(
                        "Cannot extract target grid name from mapping file %s"
                        % (c["mapping_file"])
                    )

        # Component
        c["component"] = getComponent(c["input_files"])

        # Loop over year sets
        year_sets = getYears(c["years"])
        for s in year_sets:

            c["yr_start"] = s[0]
            c["yr_end"] = s[1]
            c["ypf"] = s[1] - s[0] + 1
            c["scriptDir"] = scriptDir
            if c["subsection"]:
                sub = c["subsection"]
            else:
                sub = c["grid"]
            prefix = "ts_%s_%04d-%04d-%04d" % (
                sub,
                c["yr_start"],
                c["yr_end"],
                c["ypf"],
            )
            print(prefix)
            c["prefix"] = prefix
            scriptFile = os.path.join(scriptDir, "%s.bash" % (prefix))
            statusFile = os.path.join(scriptDir, "%s.status" % (prefix))
            settingsFile = os.path.join(scriptDir, "%s.settings" % (prefix))
            skip = checkStatus(statusFile)
            if skip:
                continue

            # Create script
            with open(scriptFile, "w") as f:
                f.write(template.render(**c))

            with open(settingsFile, "w") as sf:
                p = pprint.PrettyPrinter(indent=2, stream=sf)
                p.pprint(c)
                p.pprint(s)

            if not c["dry_run"]:
                # Submit job
                jobid = submitScript(scriptFile)

                if jobid != -1:
                    # Update status file
                    with open(statusFile, "w") as f:
                        f.write("WAITING %d\n" % (jobid))
