/**
 * drawdown.js
 * (c) Adam Leggett
 *
 * Functions to convert markdown to html
 */

function markdown(src) {
  var rx_lt = /</g;
  var rx_gt = />/g;
  var rx_space = /\t|\r|\uf8ff/g;
  var rx_escape = /\\([\\\|`*_{}\[\]()#+\-~])/g;
  var rx_hr = /^([*\-=_] *){3,}$/gm;
  var rx_blockquote = /\n *&gt; *([^]*?)(?=(\n|$){2})/g;
  var rx_list = /\n( *)(?:[*\-+]|((\d+)|([a-z])|[A-Z])[.)]) +([^]*?)(?=(\n|$){2})/g;
  var rx_listjoin = /<\/(ol|ul)>\n\n<\1>/g;
  var rx_highlight = /(^|[^A-Za-z\d\\])(([*_])|(~)|(\^)|(--)|(\+\+)|`)(\2?)([^<]*?)\2\8(?!\2)(?=\W|_|$)/g;
  var rx_code = /\n((```|~~~).*\n?([^]*?)\n?\2|(( {4}.*?\n)+))/g;
  var rx_link = /((!?)\[(.*?)\]\((.*?)( ".*")?\)|\\([\\`*_{}\[\]()#+\-.!~]))/g;
  var rx_table = /\n(( *\|.*?\| *\n)+)/g;
  var rx_thead = /^.*\n( *\|( *\:?-+\:?-+\:? *\|)* *\n|)/;
  var rx_row = /.*\n/g;
  var rx_cell = /\||(.*?[^\\])\|/g;
  var rx_heading = /(?=^|>|\n)([>\s]*?)(#{1,6}) (.*?)( #*)? *(?=\n|$)/g;
  var rx_para = /(?=^|>|\n)\s*\n+([^<]+?)\n+\s*(?=\n|<|$)/g;
  var rx_stash = /-\d+\uf8ff/g;

  function replace(rex, fn) {
    src = src.replace(rex, fn);
  }

  function element(tag, content, attr) {
    return `<${tag}${attr ? ` ${attr}` : ''}>${content}</${tag}>`;
  }

  function blockquote(src) {
    return src.replace(rx_blockquote, function (all, content) {
      return element('blockquote', blockquote(highlight(content.replace(/^ *&gt; */gm, ''))));
    });
  }

  function list(src) {
    return src.replace(rx_list, function (all, ind, ol, num, low, content) {
      var entry = element(
        'li',
        highlight(
          content
            .split(RegExp('\n ?' + ind + '(?:(?:\\d+|[a-zA-Z])[.)]|[*\\-+]) +', 'g'))
            .map(list)
            .join('</li><li>')
        )
      );

      return (
        '\n' +
        (ol
          ? '<ol start="' +
            (num
              ? ol + '">'
              : parseInt(ol, 36) -
                9 +
                '" style="list-style-type:' +
                (low ? 'low' : 'upp') +
                'er-alpha">') +
            entry +
            '</ol>'
          : element('ul', entry))
      );
    });
  }

  function highlight(src) {
    return src.replace(rx_highlight, function (all, _, p1, emp, sub, sup, small, big, p2, content) {
      return (
        _ +
        element(
          emp
            ? p2
              ? 'strong'
              : 'em'
            : sub
            ? p2
              ? 's'
              : 'sub'
            : sup
            ? 'sup'
            : small
            ? 'small'
            : big
            ? 'big'
            : 'code',
          highlight(content)
        )
      );
    });
  }

  function unesc(str) {
    return str.replace(rx_escape, '$1');
  }

  var stash = [];
  var si = 0;

  src = '\n' + src + '\n';

  replace(rx_lt, '&lt;');
  replace(rx_gt, '&gt;');
  replace(rx_space, '  ');

  // code
  replace(rx_code, function (all, p1, p2, p3, p4) {
    stash[--si] = element('pre', element('code', p3 || p4.replace(/^ {4}/gm, '')));
    return si + '\uf8ff';
  });

  // blockquote
  src = blockquote(src);

  // horizontal rule
  replace(rx_hr, '<hr/>');

  // list
  src = list(src);
  replace(rx_listjoin, '');

  // link or image
  replace(rx_link, function (all, p1, p2, p3, p4, p5, p6) {
    stash[--si] = p4
      ? p2
        ? '<img src="' + p4 + '" alt="' + p3 + '"/>'
        : '<a href="' + p4 + '">' + unesc(highlight(p3)) + '</a>'
      : p6;
    return si + '\uf8ff';
  });

  function tableRows(table, align, isHeader) {
    return table.replace(rx_row, function (row, ri) {
      let col = -1;
      return element(
        'tr',
        row.replace(rx_cell, function (all, cell, ci) {
          if (!ci) return '';
          col++;
          return align[col] === 'none'
            ? element(isHeader ? 'th' : 'td', unesc(highlight(cell || '')))
            : element(
                isHeader ? 'th' : 'td',
                unesc(highlight(cell || '')),
                `align="${align[col]}"`
              );
        })
      );
    });
  }
  // table
  replace(rx_table, function (all, table) {
    var sep = table.match(rx_thead)[1];
    var align = sep
      .split('|')
      .map((x) => x.trim().replace(/-+/g, '-'))
      .filter((x) => x.length > 0)
      .map((x) => {
        switch (x) {
          case ':-':
            return 'left';
          case '-:':
            return 'right';
          case ':-:':
            return 'center';
          default:
            return 'none';
        }
      });
    var [head, body] = table.split(sep);
    var elHead = element('thead', tableRows(head, align, true));
    var elBody = element('tbody', tableRows(body, align));
    var elTable = element('table', elHead + elBody);
    return '\n' + element('div', elTable, `style="overflow-x:auto"`);
  });

  // heading
  replace(rx_heading, function (all, _, p1, p2) {
    return _ + element('h' + p1.length, unesc(highlight(p2)));
  });

  // paragraph
  replace(rx_para, function (all, content) {
    return element('p', unesc(highlight(content)));
  });

  // stash
  replace(rx_stash, function (all) {
    return stash[parseInt(all)];
  });

  return src.trim();
}
