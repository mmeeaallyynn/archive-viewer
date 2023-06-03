/* application.vala
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
    public class Application : Adw.Application {
        string ui = """
            <interface>
                <object class="GtkWindow" id="window">
                    <child>
                        <object class="GtkHeaderBar" id="titlebar">
                          <property name="title-widget">
                            <object class="GtkLabel" id="titlelabel">
                              <property name="single-line-mode">True</property>
                              <property name="ellipsize">end</property>
                              <property name="width-chars">5</property>
                              <style>
                                <class name="title"/>
                              </style>
                            </object>
                          </property>
                          <child>
                            <object class="GtkButton" id="upbutton">
                              <property name="label">↑</property>
                            </object>
                          </child>
                        </object>

                        <object class="GtkScrolledWindow" id="scrolled_window">
                            <child>
                                <object class="AdwClamp" id="clamp">
                                </object>
                            </child>
                        </object>
                    </child>
                </object>
            </interface>
        """;
        // this needs to be accessible from the outside to handle ctrl-c cleanup
        // this could potentially be made into a list where each window gets one element later on
        public static ArchiveX.Archive archive = new ArchiveX.Archive ();
        Gtk.Label titlelabel;
        Gtk.MultiSelection selection;
        static string[] column_titles = {
            "file",
            "size",
            "type",
            "modified"
        };

        public Application () {
            Object (application_id: "local.adw.Test", flags: ApplicationFlags.FLAGS_NONE);
        }

        construct {
            ActionEntry[] action_entries = {
                { "about", this.on_about_action },
                { "preferences", this.on_preferences_action },
                { "quit", this.quit }
            };
            this.add_action_entries (action_entries, this);
            this.set_accels_for_action ("app.quit", {"<primary>q"});
        }

        async void open_archive (string filename) {
            try {
                this.archive.close ();
                this.archive.open (filename);
            }
            catch (GLib.FileError e) {
                stderr.printf ("Can't create tmpdir: %s\n", e.message);
                this.archive.close ();
            }
            catch (ArchiveX.ArchiveFSError e) {
                stderr.printf ("Can't mount archive: %s\n", e.message);
                this.archive.close ();
            }
            catch (GLib.Error e) {
                stderr.printf ("Can't launch archivefs: %s\n", e.message);
                this.archive.close ();
            }
        }

        Gtk.ColumnView create_column_view () {
            this.selection  = new Gtk.MultiSelection  (this.archive.list);
            var column_view = new Gtk.ColumnView (selection);
            column_view.set_vexpand (true);
            column_view.activate.connect ((position) => {
                var info = this.archive.list.get_item (position) as GLib.FileInfo;
                if (info.get_file_type () == GLib.FileType.DIRECTORY) {
                    try {
                        this.archive.chdir (info.get_name ());
                        this.titlelabel.set_text (this.archive.get_current_path ());
                    }
                    catch (GLib.Error e) {
                        stderr.printf ("Can't open %s: %s\n", info.get_name (), e.message);
                    }
                }
                stdout.printf ("activated %s\n", info.get_name ());
            });


            foreach (string title in Application.column_titles) {
                var factory = new Gtk.SignalListItemFactory ();
                factory.setup.connect ((factory, list_item) => {
                    var label = new Gtk.Label ("unknown");
                    label.set_xalign (0);
                    list_item.set_child (label);
                });
                factory.bind.connect((factory, list_item) => {
                    var label = list_item.get_child () as Gtk.Label;
                    var entry = list_item.get_item () as GLib.FileInfo;

                    switch (title) {
                    case "file":
                        label.label = entry.get_name ();
                        break;
                    case "size":
                        label.label = entry.get_size ().to_string ();
                        break;
                    case "type":
                        label.label = entry.get_content_type ();
                        break;
                    case "modified":
                        var datetime = entry.get_modification_date_time ();
                        if (datetime != null) {
                            label.label = datetime.format ("%d %B %Y, %R");
                        }
                        break;
                    }
                });

                var column = new Gtk.ColumnViewColumn (title, factory);
                column_view.append_column (column);
            }

            return column_view;
        }

        void setup_dnd (Gtk.ColumnView list) {
            var drop_target = new Gtk.DropTarget (typeof (GLib.File), Gdk.DragAction.COPY);
            drop_target.motion.connect ((x, y) => {
                return Gdk.DragAction.COPY;
            });
            drop_target.drop.connect ((v, x, y) => {
                var f = v as GLib.File;
                var info = f.query_info ("*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                stdout.printf ("drop %s\n", f.get_path ());
                this.open_archive.begin (f.get_path ());
                return true;
            });
            var drag_source = new Gtk.DragSource ();
            drag_source.drag_end.connect ((source, drag) => {
                stdout.printf ("end\n");
            });
            drag_source.drag_begin.connect ((source, drag) => {
                var selected = this.selection.get_selection ();

                for (uint i = 0; i < selected.get_size (); i++) {
                    stdout.printf ("%u\n", selected.get_nth (i));
                }
            });
            drag_source.prepare.connect ((source, x, y) => {
                var selected = this.selection.get_selection ();

                var files = new GLib.SList<GLib.File> ();
                Gdk.ContentProvider[] content_providers = new Gdk.ContentProvider[selected.get_size ()];

                for (uint i = 0; i < selected.get_size (); i++) {
                    var info = this.archive.list.get_item (selected.get_nth (i)) as GLib.FileInfo;
                    var full_path = this.archive.get_path_in_fs (info.get_name ());
                    var f = GLib.File.new_for_path (full_path);
                    files.append (f);
                    var val = Value (typeof (GLib.File));
                    val.set_instance (f);
                    content_providers[i] = new Gdk.ContentProvider.for_value (val);
                }
                var file_list = new Gdk.FileList.from_list (files);

                var finalc = new Gdk.ContentProvider.union (content_providers);
                return finalc;
            });
            list.add_controller (drag_source);
            list.add_controller (drop_target);
        }

        public override void activate () {
            base.activate ();
            var b = new Gtk.Builder.from_string (ui, ui.length);
            var win = b.get_object ("window") as Gtk.Window;
            var area = b.get_object ("clamp") as Adw.Clamp;
            var titlebar = b.get_object ("titlebar") as Gtk.HeaderBar;
            this.titlelabel = b.get_object ("titlelabel") as Gtk.Label;
            var upbutton = b.get_object ("upbutton") as Gtk.Button;
            upbutton.clicked.connect (() => {
                try {
                    this.archive.chdir ("..");
                    this.titlelabel.set_text (this.archive.get_current_path ());
                }
                catch (GLib.Error e) {
                    stderr.printf ("Can't cd: %s", e.message);
                }
            });

            this.titlelabel.set_text ("/");

            win.set_titlebar (titlebar);

            var list = this.create_column_view ();
            this.setup_dnd (list);

            area.set_child (list);
            win.set_application (this);

            win.present ();
        }

        public override void shutdown () {
            stdout.printf ("shutdown!\n");
            this.archive.close ();
            base.shutdown ();
        }

        private void on_about_action () {
            string[] developers = { "mealynn" };
            var about = new Adw.AboutWindow () {
                transient_for = this.active_window,
                application_name = "adwvalatest",
                application_icon = "local.adw.Test",
                developer_name = "mealynn",
                version = "0.1.0",
                developers = developers,
                copyright = "© 2023 mealynn",
            };

            about.present ();
        }

        private void on_preferences_action () {
            message ("app.preferences action activated");
        }
    }
}
