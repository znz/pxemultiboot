#!/usr/bin/ruby
# -*- coding: utf-8 -*-
=begin
= PXE Multi Boot Helper
== Requirements
* Ruby 1.8.x
* curl

== Usage
* ruby pxemultiboot-helper.rb

== License
The MIT License

Copyright (c) 2009 Kazuhiro NISHIYAMA

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
=end

require "fileutils"
require "optparse"

class PxeMultiBootHelper
  def initialize
    setup_default_mirror
    set_top_dir
    set_verbose
  end

  def setup_default_mirror
    @mirror = {
      :debian => "http://ftp.jp.debian.org/debian",
      :syslinux => "http://www.kernel.org/pub/linux/utils/boot/syslinux",
    }
  end

  def mirror(target)
    @mirror[target]
  end

  def set_verbose(flag=true)
    if flag
      @verbose = true
      @fu = ::FileUtils::Verbose
    else
      @verbose = false
      @fu = ::FileUtils
    end

    def @fu.cp(src, dest, options={})
      options[:preserve] = true # always preserve
      super(src, dest, options)
    end
  end

  def set_top_dir(top_dir='.')
    @tftpboot_dir = File.expand_path('tftpboot', top_dir)
    @download_dir = File.expand_path('download', top_dir)
    @boot_screens = File.join(tftpboot_dir, "boot-screens")
  end

  attr_reader :fu
  attr_reader :tftpboot_dir, :download_dir, :boot_screens

  def setup_directories
    fu.mkpath(download_dir) unless File.directory?(download_dir)
    fu.mkpath(boot_screens) unless File.directory?(boot_screens)
    fu.chdir(tftpboot_dir)
  end

  def xsystem(*args)
    puts "system(#{args.inspect})"
    system(*args)
  end

  def download(path, uri)
    unless File.exist?(path)
      unless xsystem("curl", uri, "--output", path)
        fu.rm_f(path)
        raise "download failed: #{uri} to #{path}"
      end
    end
  end

  class Menu
    def initialize(menu_cfg)
      @menu_cfg = menu_cfg
      @sub_menus = []
    end

    def push_sub_menu(menu)
      @sub_menus.push(menu)
    end

    def cfg_puts(cfg_text)
      @menu_cfg_file.puts cfg_text
    end

    def menu_include(sub_cfg)
      cfg_puts "include #{sub_cfg}"
    end

    def run(parent, top)
      open(@menu_cfg, "w") do |f|
        @menu_cfg_file = f
        cfg_puts cfg_prologue if respond_to?(:cfg_prologue)
        main(parent, top)
        cfg_puts cfg_epilogue if respond_to?(:cfg_epilogue)
      end
    ensure
      @menu_cfg_file = nil
    end

    def main(parent, top)
      @sub_menus.each do |sub_menu|
        sub_menu.run(self, top)
      end
      parent.menu_include @menu_cfg
    end
  end

  def menu_include(top_menu_cfg)
    # ignore
  end

  class TopMenu < Menu
    def cfg_prologue
      <<-CFG
menu hshift 5
menu width 65

menu title PXE Boot Menu
menu background boot-screens/syslinux_splash.jpg
      CFG
    end
  end

  class Installer < Menu
    def initialize(distro, title)
      @distro = distro
      @title = title
      super("boot-screens/#{@distro}.cfg")
    end

    def cfg_prologue
      <<-CFG
menu begin #{@title} Install
	menu title #{@title} Install
	label mainmenu
		menu label ^Back..
		menu exit
      CFG
    end

    def cfg_epilogue
      "menu end"
    end
  end

  class DebianInstaller < Menu
    def initialize(suite, title, options={})
      @distro = "debian"
      @suite = suite
      @title = title
      @arch = options[:arch] || "i386"

      if options[:gtk]
        @m_gtk = "-gtk" # minus and gtk
        @slash_gtk = "/gtk" # slash and gtk
        @s_GTK = " GTK" # space and GTK
      else
        @m_gtk = @slash_gtk = @s_GTK = ""
      end

      super("boot-screens/#{@suite}-#{@arch}#{@m_gtk}.cfg")
    end

    def cfg_prologue
      <<-CFG
label mainmenu
	menu label ^Return to Top Menu
	kernel boot-screens/vesamenu.c32
	append pxelinux.cfg/default
      CFG
    end

    def mirror(top)
      top.mirror(:debian)
    end

    def extract_dir
      "#{@distro}-installer"
    end

    def installer_dir
      "#{@distro}/#{@suite}#{@m_gtk}-installer"
    end

    def netboot_uri(top)
      "#{mirror(top)}/dists/#{@suite}/main/installer-#{@arch}/current/images/netboot#{@slash_gtk}/netboot.tar.gz"
    end

    def netboot_tar_gz(top)
      "#{top.download_dir}/#{@suite}-#{@arch}#{@m_gtk}-netboot.tar.gz"
    end

    def main(parent, top)
      fu = top.fu

      top.download(netboot_tar_gz(top), netboot_uri(top))
      fu.mkpath("tmp")
      fu.chdir("tmp") do
        top.xsystem("tar", "xf", netboot_tar_gz(top), "./#{extract_dir}/")
      end
      fu.mkpath(installer_dir)
      fu.rm_rf("#{installer_dir}/#{@arch}")
      fu.mv("tmp/#{extract_dir}/#{@arch}", "#{installer_dir}/")
      fu.rmdir(extract_dir)
      fu.rmdir("tmp")

      menu_cfg = "#{installer_dir}/#{@arch}/boot-screens/menu.cfg"
      if File.exist?(menu_cfg)
        # interpid, jaunty
        # lenny
        proc_cfg_file = proc do |cfg_filename|
          File.foreach(cfg_filename) do |line|
            line.gsub!(extract_dir) { installer_dir }
            if /\s*include (\S+)/ =~ line
              if File.exist?($1)
                cfg_puts '#^^^ ' + line
                proc_cfg_file.call($1)
                cfg_puts '#$$$ ' + line
              else
                cfg_puts '#### ' + line
              end
            else
              cfg_puts line
            end
          end
        end
        proc_cfg_file.call(menu_cfg)
      else
        # dapper, hardy
        # etch
        File.foreach("#{installer_dir}/#{@arch}/pxelinux.cfg/default") do |line|
          case line
          when /^LABEL /
            cfg_puts "label #{@suite}-#{@arch}-#{$'}"
          when /^\s+(?:kernel|append)/
            cfg_puts line.gsub(extract_dir) { installer_dir }
          else
            # ignore
          end
        end
      end

      kernel = "#{@suite}#{@m_gtk}-installer/#{@arch}/boot-screens/vesamenu.c32"
      unless File.exist?(kernel)
        kernel = "boot-screens/vesamenu.c32"
      end
      parent.cfg_puts <<-CFG
label #{@suite}-#{@arch}#{@m_gtk}
	menu label #{@title} #{@arch}#{@s_GTK} Installer
	kernel #{kernel}
	append boot-screens/#{@suite}-#{@arch}#{@m_gtk}.cfg
      CFG
    end
  end # DebianInstaller

  def setup_pxelinux(ver)
    tar_gz = "#{download_dir}/syslinux-#{ver}.tar.bz2"
    download(tar_gz, "#{mirror(:syslinux)}/syslinux-#{ver}.tar.bz2")
    fu.mkpath("tmp")
    fu.chdir("tmp") do
      xsystem("tar", "xf", tar_gz)
    end
    [
      "com32/menu/vesamenu.c32",
      "com32/modules/reboot.c32",
      #"com32/modules/chain.c32",
      "memdisk/memdisk",
      "modules/poweroff.com",
      "sample/syslinux_splash.jpg",
    ].each do |file|
      to_file = "#{boot_screens}/#{File.basename(file)}"
      fu.cp("tmp/syslinux-#{ver}/#{file}", to_file)
    end
    fu.rm_f("pxelinux.0")
    fu.cp("tmp/syslinux-#{ver}/core/pxelinux.0", "pxelinux.0")
    fu.mkpath("pxelinux")
    fu.rm_f("pxelinux.cfg")
    fu.ln_sf("pxelinux", "pxelinux.cfg")
    open("pxelinux/default", "w") do |f|
      f.write <<-CFG
include boot-screens/menu.cfg
include boot-screens/misc.cfg
default boot-screens/vesamenu.c32
prompt 0
timeout 0
      CFG
    end
    open("boot-screens/misc.cfg", "w") do |f|
      f.write <<-CFG
LABEL Poweroff
      KERNEL boot-screens/poweroff.com
LABEL Reboot
      KERNEL boot-screens/reboot.c32
LABEL 1st local disk
      localboot 0x80
LABEL 2nd local disk
      localboot 0x81
LABEL floppy disk
      localboot 0x00
      CFG
    end

    fu.rm_rf("tmp/syslinux-#{ver}")
    fu.rmdir("tmp")
  end

  def run(argv)
    top_menu = TopMenu.new("#{@boot_screens}/menu.cfg")
    syslinux_ver = "3.83"

    OptionParser.new do |opts|
      opts.on("--top-dir=DIR") do |v|
        set_top_dir(v)
      end

      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        set_verbose(v)
      end

      debian_suites = {
        "sid" => "sid (unstable)",
        "squeeze" => "squeeze (testing)",
        "lenny" => "lenny (stable)",
        "etch" => "etch (oldstable)",
        #"etchnhalf" => "etchnhalf",
      }
      opts.on("--debian #{debian_suites.keys.join(',')}", Array, "Debian GNU/Linux Installer") do |list|
        debian = Installer.new("debian", "Debian GNU/Linux")
        top_menu.push_sub_menu(debian)
        list.each do |suite|
          case suite
          when "etchnhalf"
          else
            title = debian_suites[suite]
            [
              DebianInstaller.new(suite, title),
              DebianInstaller.new(suite, title, :arch => "amd64"),
              DebianInstaller.new(suite, title, :gtk => true),
              DebianInstaller.new(suite, title, :arch => "amd64", :gtk => true),
            ].each do |d_i|
              debian.push_sub_menu(d_i)
            end
          end
        end
      end

      opts.on("--syslinux=VERSION", "Specify SYSLINUX version (default:#{syslinux_ver})") do |v|
        syslinux_ver = v
      end
    end.parse!(argv)

    setup_directories
    setup_pxelinux(syslinux_ver)
    top_menu.run(self, self)
  end
end

if __FILE__ == $0
  helper = PxeMultiBootHelper.new
  helper.run(ARGV)
end
