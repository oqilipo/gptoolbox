function [P,C] = parse_path(dstr)
  % [P,C] = parse_path(dstr)
  %
  % Inputs:
  %   dstr  string of the value of the 'd' attribute
  % Outputs:
  %   P  #P by 2 list of control point locations
  %   C  #C by 4 list of indices into P of cubics
  %


  function [x,dstr] = parse_x(dstr)
    [x,count,~,pos] = sscanf(dstr,'%g',1);
    if count~= 1
      x = [];
      return;
    end
    dstr = dstr(pos:end);
    dstr = strip(strip(dstr,'left',','),'left',' ');
  end
  function [xy,dstr] = parse_xy(dstr)
    [x,dstr] = parse_x(dstr);
    [y,dstr] = parse_x(dstr);
    if isempty(y) 
      xy = [];
      return;
    end
    xy = [x y];
  end
  function [key,dstr] = parse_key(dstr)
    % only support open cubic Bezier splines for now
    keys = 'CcHhLlMmSsVvZzQqAaTt';
    [key,count,~,pos] = sscanf(dstr,'%c',1);
    if count~= 1 
      key = [];
    elseif ~ismember(key,keys)
      key = [];
    else
      dstr = dstr(pos:end);
    end
  end

  dstr = strrep(dstr,'\n',' ');
  dstr = strrep(dstr,',',' ');

  [key,dstr] = parse_key(strtrim(dstr));
  assert(key == 'M' || key == 'm','First key must be M or m');
  [P,dstr] = parse_xy(dstr);
  mi = size(P,1);
  % Pabs will track the current cursor position
  Pabs = P(end,:);
  C = [];
  z_seen = false;
  % I guess L is some kind of default...
  prev_key = char('L' + (key-'M'));
  while ~isempty(dstr)
    [key,dstr] = parse_key(dstr);
    % A command letter may be eliminated if an identical command letter would
    % otherwise precede it; for instance, the following contains an unnecessary
    % second "L" command:
    if isempty(key) && ~isempty(prev_key)
      key = prev_key;
    end
    switch key
    case {'A','a'}
      [Z,count,~,pos] = sscanf(dstr,'%g',7);
      assert(count == 7,'Expected 7 values for A,a command');
      % O(n) :-(
      dstr = strtrim(dstr(pos:end));

      rx = Z(1);
      ry = Z(2);
      % x-axis rotation
      phi = Z(3);
      % large-arc-flag
      large_arc = Z(4);
      % sweep-flag
      sweep = Z(5);
      Pnext = (key=='a')*Pabs + [Z(6) Z(7)];

      if ~isequal(Pabs,Pnext)
        [Pe,Ce] = arc_to_cubics(Pabs,Pnext,rx,ry,phi,large_arc,sweep);

        C = [C;size(P,1)+Ce-1];
        P = [P;Pe(2:end,:)];

        Pabs = P(end,:);
      end
    case {'T','t'}
      assert(prev_key == 'Q' || prev_key == 'q' || prev_key == 'T' || prev_key == 't',...
        'T,t command must be preceded by Q,q or T,t command');
      Q1 = Pabs;
      Q2 = Pabs + (Pabs-Qprev);
      [Q3,dstr] = parse_xy(dstr);
      Q3 = Q3 + (key=='t')*Pabs;
      Q = [Q1;Q2;Q3];
      CQ = quadratic_to_cubic(Q);
      C = [C;size(P,1)+[0 1 2 3]];
      P = [P;CQ(2:end,:)];
      Qprev = Q(2,:);
      Pabs = P(end,:);

    case {'Q','q'}
      Q1 = Pabs;
      [Q2,dstr] = parse_xy(dstr);
      [Q3,dstr] = parse_xy(dstr);
      Q = [Q1;[Q2;Q3] + (key=='q')*Pabs];
      CQ = quadratic_to_cubic(Q);
      C = [C;size(P,1)+[0 1 2 3]];
      P = [P;CQ(2:end,:)];

      Qprev = Q(2,:);
      Pabs = P(end,:);

    case {'C','c'}
      C = [C;size(P,1)+[0 1 2 3]];
      [P(end+1,:),dstr] = parse_xy(dstr);
      [P(end+1,:),dstr] = parse_xy(dstr);
      [P(end+1,:),dstr] = parse_xy(dstr);
      if key == 'c'
        P(end-2:end,:) = P(end-2:end,:) + Pabs;
      end
      Pabs = P(end,:);
    case {'L','l','V','v','H','h','Z','z'}
      if (key == 'Z' || key == 'z')
        %assert(isempty(dstr),'Z Should be last key');
        % gobble white space
        dstr = strip(dstr);
      end
      % augh I hate that I'm using epsilon here. probably the interp1 above is
      % leading to small numerical noise.
      if (key == 'Z' || key == 'z') && size(P,1)==mi
        % degenerate single point, ignore
      elseif (key == 'Z' || key == 'z') && sum((P(end,:)-P(mi,:)).^2)<eps
        % close up naturally by identifying first and last point
        if ~isempty(C)
          C(end,4) = mi;
        end
        % Pop last point
        P = P(1:end-1,:);
        Pabs = P(mi,:);
      else
        C = [C;size(P,1)+[0 1 2 3]];
        switch key
        case {'L','l'}
          [XY,dstr] = parse_xy(dstr);
          Pnext = (key=='l')*Pabs + XY;
        case {'V','v'}
          [Y,dstr] = parse_x(dstr);
          Pnext = [1 (key=='v')].*Pabs + [0 Y];
        case {'H','h'}
          [X,dstr] = parse_x(dstr);
          Pnext = [(key=='h') 1].*Pabs + [X 0];
        case {'Z','z'}
          % I don't see how Z or z are different.
          % Don't parse xy, connect to beginning 
          Pnext = P(mi,:);
        end
        P(end+1,:) = Pabs + (1/3)*(Pnext-Pabs);
        P(end+1,:) = Pabs + (2/3)*(Pnext-Pabs);
        P(end+1,:) = Pnext;
        Pabs = P(end,:);
      end
    case {'S','s'}
      C = [C;size(P,1)+[0 1 2 3]];
      if ismember(prev_key,'SsCc')
        P(end+1,:) = P(end,:)+ P(end,:)-P(end-1,:);
      else
        P(end+1,:) = P(end,:);
      end
      [P(end+1,:),dstr] = parse_xy(dstr);
      [P(end+1,:),dstr] = parse_xy(dstr);
      if key == 's'
        P(end-1:end,:) = P(end-1:end,:) + Pabs;
      end
      Pabs = P(end,:);
    case {'M','m'}
      [Pnext,dstr] = parse_xy(dstr);
      Pm = Pnext+(key=='m')*Pabs;
      P = [P;Pm];
      mi = size(P,1);
      Pabs = P(end,:);
      % Augh this can even happen after 'mz', set key here so below prev_key is
      % correct.
      key = char('L' + (key-'M'));
    otherwise
      error('%c key not supported',key)
    end
    %key
    %clf;hold on;arrayfun(@(c) set(plot_cubic(P(C(c,:),:)),'Color','b'),1:size(C,1));hold off;
    %pause
    prev_key = key;
  end
    

end
