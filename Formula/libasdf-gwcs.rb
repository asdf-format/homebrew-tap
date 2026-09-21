class LibasdfGwcs < Formula
  desc "GWCS plugin for libasdf"
  homepage "https://libasdf-gwcs.readthedocs.io/"
  url "https://github.com/asdf-format/libasdf-gwcs/releases/download/0.1.0/libasdf-gwcs-0.1.0.tar.gz"
  sha256 "d671b94d53fe66dd4a9794d511b768c2c7f77c7d571af01ea3db34d82c534679"
  license "BSD-3-Clause"

  head do
    url "https://github.com/asdf-format/libasdf-gwcs.git", branch: "main"

    depends_on "autoconf" => :build
    depends_on "automake" => :build
    depends_on "libtool" => :build
  end

  depends_on "pkgconf" => [:build, :test]
  depends_on "libasdf"
  depends_on "libfyaml"

  def install
    system "./autogen.sh" if build.head?
    system "./configure", "--disable-silent-rules", "--disable-docs", *std_configure_args
    system "make"
    system "make", "check"
    system "make", "install"
  end

  test do
    (testpath/"test.asdf").write <<~YAML
      #ASDF 1.0.0
      #ASDF_STANDARD 1.6.0
      %YAML 1.1
      %TAG ! tag:stsci.edu:
      --- !asdf/core/asdf-1.1.0
      wcs: !gwcs/wcs-1.4.0
        name: test
        steps:
        - !gwcs/step-1.3.0
          frame: !gwcs/frame2d-1.2.0 {name: detector}
          transform: !asdf/transform/concatenate-1.2.0
            forward:
            - !asdf/transform/scale-1.2.0 {factor: 2.0}
            - !asdf/transform/scale-1.2.0 {factor: 3.0}
        - !gwcs/step-1.3.0
          frame: !gwcs/frame2d-1.2.0 {name: world}
          transform: null
      ...
    YAML

    (testpath/"test.c").write <<~C
      #include <stdio.h>
      #include <asdf.h>
      #include <asdf/gwcs/gwcs.h>

      int main(void) {
          asdf_file_t *file = asdf_open("test.asdf", "r");
          asdf_gwcs_t *wcs = NULL;
          if (!file || asdf_get_gwcs(file, "wcs", &wcs) != ASDF_VALUE_OK)
              return 1;
          asdf_gwcs_eval_t *eval = asdf_gwcs_eval_create(file, wcs, NULL, NULL);
          double x = 1.5, y = 2.5;
          if (!eval || asdf_gwcs_eval_2d(eval, &x, &y, &x, &y, 1) != ASDF_GWCS_OK)
              return 1;
          printf("%g %g\\n", x, y);
          return 0;
      }
    C

    flags = shell_output("pkgconf --cflags --libs libasdf-gwcs").chomp.split
    system ENV.cc, "test.c", *flags, "-o", "test"
    assert_equal "3 7.5\n", shell_output("./test")
  end
end
