namespace ArchiveX {
    public errordomain ArchiveFSError {
        NOT_MOUNTED,
        NOT_UNMOUNTED
    }

    public class Archive {
        public string tmp_dir;
        Gee.ArrayList<string> current_path;
        bool is_mounted = false;
        public GLib.ListStore list = new GLib.ListStore (typeof (GLib.FileInfo));

        public string get_current_path() {
            return this.current_path.fold<string> ((element, acc) => acc + "/" + element, "");
        }

        public string get_path_in_fs (string filepath) {
            var full_path = this.current_path.fold<string> ((element, acc) => acc + "/" + element, "");
            return @"$(this.tmp_dir)/$(full_path)/$(filepath)";
        }

        public void open (string path) throws GLib.FileError, GLib.Error, ArchiveFSError {
            this.is_mounted = true;
            var path_list = path.split ("/");
            var name = path_list[path_list.length - 1];
            this.tmp_dir = GLib.DirUtils.make_tmp (@"archivex-$name-XXXXXX");
            this.current_path = new Gee.ArrayList<string> ();

            var sp = new Subprocess.newv (
                { "archivefs", path, this.tmp_dir },
                SubprocessFlags.STDOUT_PIPE);
            sp.wait ();

            if (!sp.get_successful ()) {
                // TODO: improve error message
                throw new ArchiveFSError.NOT_MOUNTED ("Not mounted");
            }

            this.chdir ("/");
        }

        public void chdir (string path) throws GLib.Error {
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

            FileInfo info = null;
            var dir = GLib.File.new_for_path (this.tmp_dir + "/" + total_path);
            FileEnumerator enumerator = dir.enumerate_children (
                "*",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS);

            while ((info = enumerator.next_file ()) != null) {
                this.list.append (info);
            }
        }

        public void close () {
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
