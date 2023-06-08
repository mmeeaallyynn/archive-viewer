namespace ArchiveX {
    public errordomain ArchiveFSError {
        NOT_MOUNTED,
        NOT_UNMOUNTED
    }

    // TODO: edit archives:
    // create second folder as overlay
    // create new archive from both folders on save

    /* Represents an archive
     *
     * This class only mounts an archive into a tmp folder.
     * archivefs handles reading and extracting the contents.
     */
    public class Archive {
        // TODO: complete this list
        public static string[] content_types = {
            "application/x-compressed-tar",
            "application/zip",
            "application/vnd.rar",
            "application/x-bzip-compressed-tar",
            "application/x-7z-compressed",
            "application/x-cd-image",
            "application/x-tar"
        };
        public string name { public get; set; }
        public string tmp_dir;
        Gee.ArrayList<string> current_path;
        bool is_mounted = false;
        public GLib.ListStore list = new GLib.ListStore (typeof (GLib.FileInfo));
        Gee.HashMap<string, Gee.List<GLib.FileInfo>> dir_cache = new Gee.HashMap<string, Gee.List<GLib.FileInfo>> ();
        GLib.Cancellable? cancellable = null;
        public signal void load_finished ();
        public signal void load_started ();


        public string get_current_path() {
            return this.current_path.fold<string> ((element, acc) => acc + "/" + element, "");
        }

        public string get_path_in_fs (string filepath) {
            var full_path = this.current_path.fold<string> ((element, acc) => acc + "/" + element, "");
            return @"$(this.tmp_dir)/$(full_path)/$(filepath)";
        }

        public async void open (string path) throws GLib.FileError, GLib.Error, ArchiveFSError {
            this.cancellable = new Cancellable ();
            this.is_mounted = true;
            var path_list = path.split ("/");
            this.name = path_list[path_list.length - 1];
            this.tmp_dir = GLib.DirUtils.make_tmp (@"archivex-$name-XXXXXX");
            this.current_path = new Gee.ArrayList<string> ();

            var sp = new Subprocess.newv (
                { "archivefs", path, this.tmp_dir },
                SubprocessFlags.STDOUT_PIPE);

            // TODO: Mounting should be stopped, when the wait was cancelled
            var success = yield sp.wait_check_async (cancellable);

            if (!sp.get_successful ()) {
                // TODO: improve error message
                throw new ArchiveFSError.NOT_MOUNTED ("Not mounted");
            }

            yield this.chdir ("..");
        }

        public async void chdir (string path) throws GLib.Error {
            this.load_started ();
            if (path == "..") {
                if (this.current_path.size > 0) {
                    this.current_path.remove_at (this.current_path.size - 1);
                }
            }
            else {
                this.current_path.add (path);
            }

            var total_path = this.current_path.fold<string> ((element, acc) => acc + "/" + element, "");
            this.list.remove_all ();
            if (this.dir_cache.has_key (total_path)) {
                debug ("load from cache: %s", total_path);
                var cache_entry = this.dir_cache.get (total_path);
                foreach (var info in cache_entry) {
                    this.list.append (info);
                }
            }
            else {
                var cache_entry = new Gee.ArrayList<GLib.FileInfo> ();
                var dir = GLib.File.new_for_path (this.tmp_dir + "/" + total_path);
                FileEnumerator enumerator = yield dir.enumerate_children_async (
                    "*",
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS);

                while (true) {
                    var file_infos = yield enumerator.next_files_async (10, Priority.DEFAULT, null);

                    if (file_infos == null) {
                        break;
                    }

                    foreach (var info in file_infos) {
                        cache_entry.add (info);
                        this.list.append (info);
                    }
                }
                debug ("create cache entry: %s", total_path);
                this.dir_cache.set (total_path, cache_entry);
            }
            this.load_finished ();
        }

        public void close () {
            this.dir_cache.clear ();
            if (this.cancellable != null) {
                this.cancellable.cancel ();
            }
            if (!this.is_mounted) {
                return;
            }
            try {
                var sp = new Subprocess.newv (
                    { "umount", this.tmp_dir },
                    SubprocessFlags.STDOUT_PIPE);
                sp.wait ();
                if (!sp.get_successful ()) {
                    stderr.printf ("Can't unmount\n");
                }
            }
            catch {
                stderr.printf ("Can't unmount\n");
            }
            this.list.remove_all ();

            GLib.DirUtils.remove (this.tmp_dir);
            this.is_mounted = false;
        }
    }
}
