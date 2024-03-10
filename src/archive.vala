/* archive.vala
 *
 * Copyright 2023 mealynn
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ArchiveX {
    public errordomain ArchiveFSError {
        NOT_MOUNTED,
        NOT_UNMOUNTED
    }

    class Entry : Object {
        public GLib.FileInfo info;
        public string path;

        public Entry (FileInfo info, string path) {
            this.info = info;
            this.path = path;
        }

        public static bool compare (Object a, Object b) {
            var entry_a = a as Entry;
            var entry_b = b as Entry;
            if (entry_a == null || entry_b == null) {
                return false;
            }

            try {
                // remove duplicate slashes from the path
                var r = new GLib.Regex ("/+");
                string clean_path_a = r.replace (entry_a.path, entry_a.path.length, 0, "/");
                string clean_path_b = r.replace (entry_b.path, entry_b.path.length, 0, "/");
                return clean_path_a == clean_path_b;
            }
            catch (GLib.RegexError e) {
                warning ("Can't clean path string: %s", e.message);
                return false;
            }
        }
    }

    // TODO: edit archives:
    // create second folder as overlay
    // create new archive from both folders on save

    /** Represents an archive
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
        public GLib.ListStore list = new GLib.ListStore (typeof (Entry));

        string tmp_dir;
        bool is_mounted = false;
        Gee.ArrayList<string> current_path;
        Gee.HashMap<string, Gee.List<Entry>> dir_cache = new Gee.HashMap<string, Gee.List<Entry>> ();
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
                var cache_entry = new Gee.ArrayList<Entry> ();
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
                        var file_path = this.tmp_dir + "/" + total_path + "/" + info.get_name ();
                        var entry = new Entry (info, file_path);

                        cache_entry.add (entry);
                        this.list.append (entry);
                    }
                }
                debug ("create cache entry: %s", total_path);
                this.dir_cache.set (total_path, cache_entry);
            }
            this.load_finished ();
        }

        public void add_file (string path) {
            var file = File.new_for_path (path);
            GLib.FileInfo info;
            try {
                info = file.query_info ("*", GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
            }
            catch (GLib.Error e) {
                warning ("Can't add file: %s", e.message);
                return;
            }
            var entry = new Entry (info, path);

            uint position;
            var contains = this.list.find_with_equal_func (entry, Entry.compare, out position);

            if (!contains) {
                var cache_entry = this.dir_cache.get (this.get_current_path ());
                cache_entry.add (entry);
                this.list.append (entry);
            }
        }

        public void close () {
            // cancel active chdir operation
            if (this.cancellable != null) {
                this.cancellable.cancel ();
            }
            if (!this.is_mounted) {
                return;
            }
            this.dir_cache.clear ();
            // try to unmount
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

            // try to delete the remaining folder
            try {
                ArchiveX.delete_recursive (this.tmp_dir);
            }
            catch (GLib.Error e) {
                warning ("Can't delete tmp directory %s", e.message);
            }
            this.is_mounted = false;
        }

        public void save (string destination) {

        }
    }

    void delete_recursive (string path) throws GLib.Error {
        var dir = GLib.File.new_for_path (path);

        var this_info = dir.query_info ("*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
        if (this_info.get_file_type () == GLib.FileType.DIRECTORY) {
            FileEnumerator enumerator = dir.enumerate_children (
                "*",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS);

            GLib.FileInfo file_info;
            while ((file_info = enumerator.next_file (null)) != null) {
                delete_recursive (path + "/" + file_info.get_name ());
            }
        }
        dir.delete (null);
    }
}
