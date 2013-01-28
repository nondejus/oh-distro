function runGraspOptSinglePoolService(no_of_workers)

drc_path= getenv('DRC_PATH');% set this in startup.m
%filename = [drc_path 'models/mit_gazebo_models/mit_robot_hands/drake_urdfs/irobot_hand_drake.sdf'];
%filename = [drc_path 'models/mit_gazebo_models/mit_robot_hands/drake_urdfs/irobot_hand_drake.sdf'];
r_filename = [drc_path 'models/mit_gazebo_models/mit_robot_hands/drake_urdfs/sandia_hand_right_drake.sdf'];
l_filename = [drc_path 'models/mit_gazebo_models/mit_robot_hands/drake_urdfs/sandia_hand_left_drake.sdf'];

options=struct();
options.ground =true;
options.floating = true;
m_l = RigidBodyModel(l_filename,options);
m_r = RigidBodyModel(r_filename,options);

dt = 0.001;
r_l = TimeSteppingRigidBodyManipulator(m_l,dt);
r_l = setSimulinkParam(r_l,'MinStep','0.0001');
r_r = TimeSteppingRigidBodyManipulator(m_r,dt);
r_r = setSimulinkParam(r_r,'MinStep','0.0001');

lcmcoder = JLCMCoder(GraspSeedOptCoder('atlas'));
nx=22; % this changes?
%channel = ['INIT_GRASP_SEED_OPT'];
channel = ['INIT_GRASP_SEED_OPT' '_' num2str(labindex)];
disp(channel);
grasp_opt_listener=LCMCoordinateFrameWCoder('atlas',nx,'x',lcmcoder);
grasp_opt_listener.subscribe(channel);

grasp_opt_status_publisher = GraspOptStatusPublisher(no_of_workers,'GRASP_OPT_STATUS');
%systime = datenum(clock)/1000;
grasp_opt_status_publisher.publish(0,labindex,true); % No simtime available here.
cnt=0;
while(1)
    rho =0.1;
    manipuland_params.xc = [0 0 0];
    usefingermask = false;
    reset_optimization = false;
    
    [x,ts] = getNextMessage(grasp_opt_listener,1);%getNextMessage(obj,timeout)
    if (~isempty(x))
        grasp_opt_status_publisher.publish(ts,labindex,false);
        fprintf('received messagage at time %f\n',ts);
        %     fprintf('state is %f\n',x);
        %      disp(grasp_opt_listener.lcmcoder.jcoder.getObjectName())
        %      disp(grasp_opt_listener.lcmcoder.jcoder.getGeometryName())
        msg = grasp_opt_listener.lcmcoder.encode(ts,x);
        if (msg.geometry_type==msg.CYLINDER)
            radius = msg.dims(1);
            cyllength = msg.dims(2);
            manipuland_params.a = [radius radius 0.5*cyllength];manipuland_params.epsilon = [1 rho]; % cylinder
        elseif(msg.geometry_type==msg.BOX)
            manipuland_params.a = 0.5*[msg.dims(1) msg.dims(2) msg.dims(3)];manipuland_params.epsilon = [rho rho];%box
        elseif(msg.geometry_type==msg.SPHERE)
            radius = msg.dims(1);
            manipuland_params.a = radius*[1 1 1];manipuland_params.epsilon = [1 1];
        end
        if(msg.contact_mask == msg.FINGERS_ONLY)
            usefingermask = true;
        else
            usefingermask = false;
        end
        
        if(msg.grasp_type ==msg.SANDIA_LEFT)
            hand_trans = [msg.l_hand_init_pose.translation.x,msg.l_hand_init_pose.translation.y,msg.l_hand_init_pose.translation.z];
            hand_rot = [msg.l_hand_init_pose.rotation.x,msg.l_hand_init_pose.rotation.y,msg.l_hand_init_pose.rotation.z,msg.l_hand_init_pose.rotation.w];
            size_x = size(r_l.getStateFrame.coordinates,1);
            size_q = size_x/2;
            ljoint_names = (char(r_l.getStateFrame.coordinates{7:size_q}));
            
            % CandidateGraspPublisher(String robot_name, String object_name, String geometry_name,int unique_id, short grasp_type, String[] l_joint_name, String[] r_joint_name, String channel)
            candidate_grasp_publisher = CandidateGraspPublisher(msg.robot_name,msg.object_name,msg.geometry_name,msg.unique_id,0,ljoint_names,[' '],'CANDIDATE_GRASP_SEED');
            
            x0 = Point(r_l.getStateFrame);
            x0 = resolveConstraints(r_l.manip,double(x0));
            x0(1:3) = hand_trans(1:3);
            q1=  hand_rot(1);
            q2 = hand_rot(2);
            q3 = hand_rot(3);
            qw = hand_rot(4);
            [x0(4),x0(5),x0(6)] = quat2angle([qw q1 q2 q3],'XYZ');
            candidate_grasp_publisher.publish(ts,hand_trans,hand_rot,x0(7:size_q));
            
            [xstar] = iterativeGraspSearch(r_l,double(x0));
            %[xstar,zstar] = iterativeGraspSearch2(r_l,double(xstar));
            
        elseif (msg.grasp_type ==msg.SANDIA_RIGHT)
            hand_trans = [msg.r_hand_init_pose.translation.x,msg.r_hand_init_pose.translation.y,msg.r_hand_init_pose.translation.z];
            hand_rot = [msg.r_hand_init_pose.rotation.x,msg.r_hand_init_pose.rotation.y,msg.r_hand_init_pose.rotation.z,msg.r_hand_init_pose.rotation.w];
            size_x = size(r_r.getStateFrame.coordinates,1);
            size_q = size_x/2;
            rjoint_names = (char(r_r.getStateFrame.coordinates{7:size_q}));
            
            % CandidateGraspPublisher(String robot_name, String object_name, String geometry_name,int unique_id, short grasp_type, String[] l_joint_name, String[] r_joint_name, String channel)
            candidate_grasp_publisher = CandidateGraspPublisher(msg.robot_name,msg.object_name,msg.geometry_name,msg.unique_id,1,[' '],rjoint_names,'CANDIDATE_GRASP_SEED');
            
            x0 = Point(r_r.getStateFrame);
            x0 = resolveConstraints(r_r.manip,double(x0));
            x0(1:3) = hand_trans(1:3);
            q1=  hand_rot(1);
            q2 = hand_rot(2);
            q3 = hand_rot(3);
            qw = hand_rot(4);
            %[qw q1 q2 q3]
            %rpy(1:3) = quat2angle([qw q1 q2 q3],'XYZ')
            [x0(4),x0(5),x0(6)] = quat2angle([qw q1 q2 q3],'XYZ');
            candidate_grasp_publisher.publish(ts,hand_trans,hand_rot,x0(7:size_q));
            [xstar] = iterativeGraspSearch(r_r,double(x0));
            %[xstar,zstar] = iterativeGraspSearch2(r_r,double(xstar));
        end
        if(~reset_optimization)
            grasp_opt_status_publisher.publish(ts,labindex,true);
        end
    end
    
    while(reset_optimization)
        if(msg.grasp_type ==msg.SANDIA_LEFT)
            hand_trans = [msg.l_hand_init_pose.translation.x,msg.l_hand_init_pose.translation.y,msg.l_hand_init_pose.translation.z];
            hand_rot = [msg.l_hand_init_pose.rotation.x,msg.l_hand_init_pose.rotation.y,msg.l_hand_init_pose.rotation.z,msg.l_hand_init_pose.rotation.w];
            x0(1:3) = hand_trans(1:3);
            q1=  hand_rot(1); q2 = hand_rot(2); q3 = hand_rot(3); qw = hand_rot(4);
            [x0(4),x0(5),x0(6)] = quat2angle([qw q1 q2 q3],'XYZ');
            [xstar] = iterativeGraspSearch(r_l,double(x0));
        elseif (msg.grasp_type ==msg.SANDIA_RIGHT)
            hand_trans = [msg.r_hand_init_pose.translation.x,msg.r_hand_init_pose.translation.y,msg.r_hand_init_pose.translation.z];
            hand_rot = [msg.r_hand_init_pose.rotation.x,msg.r_hand_init_pose.rotation.y,msg.r_hand_init_pose.rotation.z,msg.r_hand_init_pose.rotation.w];
            x0(1:3) = hand_trans(1:3);
            q1=  hand_rot(1); q2 = hand_rot(2); q3 = hand_rot(3); qw = hand_rot(4);
            [x0(4),x0(5),x0(6)] = quat2angle([qw q1 q2 q3],'XYZ');
            [xstar] = iterativeGraspSearch(r_r,double(x0));
        end
        if(~reset_optimization)
            grasp_opt_status_publisher.publish(ts,labindex,true);
        end
    end
    
    
    cnt=cnt+1;
    if(mod(cnt,2500)==0) % approx 1hz heartbeat
        if(ts)
            stamp=ts;
        else
            stamp =0;
        end
        grasp_opt_status_publisher.publish(stamp,labindex,true); % No simtime available here.
    end
    
end %end while

    function [xstar] = iterativeGraspSearch(obj,x0)
        
        
        manip = obj.manip;
        nx = manip.getNumStates();
        nq = nx/2;
        %nz = manip.num_contacts*dim;% *dim is only required when considering friction forces
        nz = manip.num_contacts;
        z0 = zeros(nz,1);
        q0 = x0(1:nq);
        
        
        problem.x0 = [q0];
        % problem.objective = @(q) 0; % feasibility problem
        problem.objective = @(q) myobj(q);
        problem.nonlcon = @(q) mycon(q);
        problem.solver = 'fmincon';
        
        acc = 1e-04; %sub-mm accuracy
        %problem.options=optimset('DerivativeCheck','on','GradConstr','on','Algorithm','interior-point','Display','iter','OutputFcn',@drawme,'TolX',1e-14,,'TolFun',acc,'TolCon',acc,'MaxFunEvals',15000);
        % problem.options=optimset('GradConstr','on','Algorithm','interior-point','Display','iter','OutputFcn',@drawme,'TolX',1e-14,'TolFun',acc,'TolCon',acc,'MaxFunEvals',15000);
        
        problem.options=optimset( 'GradObj','on','GradConstr','on','Algorithm','interior-point','Display','none','OutputFcn',@drawme,'TolX',1e-14,'TolFun',acc,'TolCon',acc,'MaxFunEvals',1500,'MaxIter',100);
        %         myOutputFcn = @(x,optimValues,state) drawme(x, optimValues, state,index);
        %         problem.options=optimset( 'GradObj','on','GradConstr','on','Algorithm','interior-point','Display','iter','OutputFcn',myOutputFcn,'TolX',1e-14,'TolFun',acc,'TolCon',acc,'MaxFunEvals',1500,'MaxIter',100);
        %
        
        %     lb_z = -1e6*ones(nz,1);
        %     lb_z(dim:dim:end) = 0; % normal forces must be >=0
        %     ub_z = 1e6*ones(nz,1);
        
        % force search to be close to starting position
        %problem.lb = [max(q0-0.05,obj.manip.joint_limit_min+0.01)];
        %problem.ub = [min(q0+0.05,obj.manip.joint_limit_max-0.01)];
        problem.lb = [obj.manip.joint_limit_min];
        problem.ub = [obj.manip.joint_limit_max];
        posbound=0.5;
        problem.lb(1)=problem.x0(1)-0.5*posbound;
        problem.lb(2)=problem.x0(2)-0.5*posbound;
        problem.lb(3)=problem.x0(3)-0.5*posbound;
        problem.ub(1)=problem.x0(1)+0.5*posbound;
        problem.ub(2)=problem.x0(2)+0.5*posbound;
        problem.ub(3)=problem.x0(3)+0.5*posbound;
        
        orientationbound=20*(pi/180);%
        problem.lb(4)=problem.x0(4)-orientationbound;
        problem.lb(5)=problem.x0(5)-orientationbound;
        problem.lb(6)=problem.x0(6)-orientationbound;
        problem.ub(4)=problem.x0(4)+orientationbound;
        problem.ub(5)=problem.x0(5)+orientationbound;
        problem.ub(6)=problem.x0(6)+orientationbound;
        
        [q_sol,~,exitflag] = fmincon(problem);
        success=(exitflag==1);
        xstar = [q_sol(1:nq); zeros(nq,1)];
        disp(exitflag)
        if(exitflag~=-1)
            reset_optimization=false;
        end
        %         if (~success)
        %             error('failed to find fixed point');
        %         end
        
        
        function stop=drawme(q,optimValues,state)
            stop=false;
            
            [new_x,new_ts] = getNextMessage(grasp_opt_listener,1);%getNextMessage(obj,timeout)
            if (~isempty(new_x))
                disp('received new msg')
                old_geometry_name = msg.geometry_name;
                old_object_name= msg.object_name;
                old_grasp_type=msg.grasp_type;
                old_unique_id=msg.unique_id;
                msg = grasp_opt_listener.lcmcoder.encode(new_ts,new_x); % overides msg
                disp((old_grasp_type))
                disp((msg.grasp_type))
                if((old_unique_id==msg.unique_id)&&...
                        (old_geometry_name==msg.geometry_name)&&...
                        (old_object_name==msg.object_name)&&...
                        (old_grasp_type==msg.grasp_type))
                    disp('same uid as before')
                    stop=true;
                    if(msg.drake_control==msg.HALT)
                        stop=true;
                    elseif ((msg.drake_control==msg.RESET)||(msg.drake_control==msg.NEW))
                        reset_optimization = true;
                        ts = new_ts;
                        x = new_x;
                    end
                else
                    disp('Ignoring new message and resetting msg')
                    stop=false;
                    msg = grasp_opt_listener.lcmcoder.encode(ts,x); % reset to old message
                end % check uid of message
            end
            
            trans = q(1:3);
            trans(1) = q(1) -manipuland_params.xc(1);
            trans(2) = q(2) -manipuland_params.xc(2);
            trans(3) = q(3) -manipuland_params.xc(3);
            
            r = q(4); p =q(5); y =q(6);
            dcm = angle2dcm(r,p,y,'XYZ');
            quat=dcm2quat(dcm);
            rot = [quat(2);quat(3);quat(4);quat(1)];
            
            if(msg.grasp_type ==msg.SANDIA_LEFT)
                angles = q(7:7+size(ljoint_names,1)-1);
            elseif(msg.grasp_type ==msg.SANDIA_RIGHT)
                angles = q(7:7+size(rjoint_names,1)-1);
            end
            
            candidate_grasp_publisher.publish(ts,trans,rot,angles);
        end
        
        function [c,ceq,GC,GCeq] = mycon(q)
            
            %[~,C,B,~,dC,~] = manip.manipulatorDynamics(q,zeros(nq,1));
            
            % Modified Rigid Body Manipulator to pass in a function pointer to
            % custom collision detection code.
            [phiC,JC] = manip.contactConstraints(q,[],@mycollisionDetect);
            [p,J,dJ] = manip.contactPositions(q);
            
            
            % ignore friction constraints for now
            %         c = 0;
            %         GC = zeros(nq,1);
            %
            %         ceq = [phiC];
            %         GCeq = [JC'];
            
            %C(X) <= 0, Ceq(X) = 0   (nonlinear constraints)
            c = [-phiC];
            GC = [-JC'];
            
            % [W,dW] = getWrenchMatrix(p,J);
            % %W is 6 x nz
            % %dW is 6*nz x nq its stacked 6 xq matrices
            % dWz =zeros(6,nq);
            % z = ones(nz,1);
            % for i=1:nz,
            %     dWi = dW(6*(i-1)+1:6*i,:); % 6xnq
            %     dWz = dWz + z(i)*dWi; % 6xnq
            % end
            
            %ceq = W*z; % 6 x1
            %GCeq = dWz';  % must be nq x 6
            
            ceq = 0;
            GCeq = zeros(nq,1);
        end
        function [f,df] = myobj(q)
            q=q(1:nq);
            %[cm,J] = obj.manip.model.getCOM(q);
            [phiC,JC] = manip.contactConstraints(q,[],@mycollisionDetect);
            [p,J,dJ] = manip.contactPositions(q);
            mask=[1:size(phiC,1)];
            if(usefingermask)
                mask =[8 10 12 13];
                %mask =[8:13];
            end
            phiC = phiC(mask);
            JC = JC(mask,:);
            f = phiC'*phiC;% + 0.1*q([7,13])'*q([7,13]); % second term penalizes finger spread
            df = [2*phiC'*JC]';
            
            f = phiC'*phiC + 0.1*q([7,13])'*q([7,13]); % second term penalizes finger spread
            addendum = 2*0.1*q';
            filter = zeros(1,nq);
            filter([7,13]) = 1;
            addendum=filter.*addendum;
            df = [2*phiC'*JC+addendum]';
        end
        
        function [pos,vel,normal,mu] = mycollisionDetect(contact_pos)
            % for each column of contact_pos, find the closest point in the world
            % geometry, and it's (absolute) position and velocity, (unit) surface
            % normal, and coefficent of friction.
            
            % for now, just implement a ground height at y=0
            n = size(contact_pos,2);
            pos = [contact_pos(1:2,:);zeros(1,n)+1];
            normal = [zeros(2,n); ones(1,n)];
            
            params= manipuland_params;
            
            % find the closest point on superellipsoid and its normal.

             %[pos,normal]=closestPointsOnZAlignedSuperEllipsoid(contact_pos,params);
            [pos,normal]=closestPointsOnZAlignedSuperEllipsoid_NumericalNormals(contact_pos,params);  
       
            
            %[pos,normal] =closestPointsOnSphere(contact_pos);
            %       tic
            %[pos,normal] =closestPointsOnSphere2(contact_pos);
            %       toc
            % Ellipsoid is 25 times slower as there is no closed form expression
            % and you have to do a root search
            % SuperEllipsoid and Torus is 500 times slower
            
            vel = zeros(3,n); % static world assumption (for now)
            mu = ones(1,n);
        end
        
        function [ps,normals]=closestPointsOnZAlignedSuperEllipsoid_NumericalNormals(p,params)
            
            xc =params.xc;
            a = params.a;
            epsilon = params.epsilon;
            n=size(p,2);
            for ind =1:n,
                q = p(:,ind)-xc(:);
                qs=approxClosestPoint_zsuperellipsoid(q,params);
                ps(:,ind) = qs+xc(:);
                
                px = qs(1); py = qs(2); pz = qs(3);
                e_rat =  epsilon(1)/epsilon(2);
                temp = e_rat*(abs(px/a(1)).^(2/epsilon(1))+abs(py/a(2)).^(2/epsilon(1))).^(e_rat-1);
                dPhix =temp.*((2/epsilon(1))*(abs(px/a(1))).^((2/epsilon(1))-1)).*sign(px/a(1))*(1/a(1));
                dPhiy =temp.*((2/epsilon(1))*(abs(py/a(2))).^((2/epsilon(1))-1)).*sign(py/a(2))*(1/a(2));
                temp2 = e_rat*(abs(pz/a(3)).^(2/epsilon(1))).^(e_rat-1);
                dPhiz =temp2.*((2/epsilon(1))*(abs(pz/a(3))).^((2/epsilon(1))-1)).*sign(pz/a(3))*(1/a(3));
                nnorm = (dPhix.^2+dPhiy.^2+dPhiz.^2).^0.5;
                
                n(1) =dPhix./nnorm;
                n(2) =dPhiy./nnorm;
                n(3) =dPhiz./nnorm;
                n=n(:);
                
                [~,ni] = geval(@(q)closestpointfun_superellipsoid(q,params),q,struct('grad_method','numerical'));
                normals(:,ind)=ni(:);
                
                %          if(sum(n(:)-ni(:))>1e-6)
                %             nanalytical = n'
                %             ni
                %          end
                
            end
        end
        function [phi] = closestpointfun_superellipsoid(p,params)
            
            xc =params.xc;
            a = params.a;
            epsilon = params.epsilon;
            q=approxClosestPoint_zsuperellipsoid(p,params);
            %   p'
            %   q'
            px = q(1); py = q(2); pz = q(3);
            %px = p(1); py = p(2); pz = p(3);
            e_rat =  epsilon(1)/epsilon(2);
            temp = e_rat*(abs(px/a(1)).^(2/epsilon(1))+abs(py/a(2)).^(2/epsilon(1))).^(e_rat-1);
            dPhix =temp.*((2/epsilon(1))*(abs(px/a(1))).^((2/epsilon(1))-1)).*sign(px/a(1))*(1/a(1));
            dPhiy =temp.*((2/epsilon(1))*(abs(py/a(2))).^((2/epsilon(1))-1)).*sign(py/a(2))*(1/a(2));
            temp2 = e_rat*(abs(pz/a(3)).^(2/epsilon(1))).^(e_rat-1);
            dPhiz =temp2.*((2/epsilon(1))*(abs(pz/a(3))).^((2/epsilon(1))-1)).*sign(pz/a(3))*(1/a(3));
            nnorm = (dPhix.^2+dPhiy.^2+dPhiz.^2).^0.5;
            
            n(1) =dPhix./nnorm;
            n(2) =dPhiy./nnorm;
            n(3) =dPhiz./nnorm;
            n=n(:);
            
            relpos = p - q;
            s = sign(sum(relpos.*n,1)); % using analytical n as approximation for calculating real normals will this work?
            phi = (sqrt(sum(relpos.^2,1)).*s)';
            
        end
        function [q]=approxClosestPoint_zsuperellipsoid(p,params)
            epsilon= params.epsilon;
            a = params.a;
            q = p(:);
            if(epsilon(2)==epsilon(1))&&(epsilon(2)~=1) %if box
                % if outside box.
                inside=(-a(1)<=q(1))&(q(1)<=a(1))& (-a(2)<=q(2))&(q(2)<=a(2))& (-a(3)<=q(3))&(q(3)<=a(3));
                if(~inside)
                    %disp('~inside')
                    for j= 1:3,
                        vert=p(j);
                        b = [-a(j) a(j)];
                        vert = max(vert,min(b));
                        vert = min(vert,max(b));
                        q(j) =vert;
                    end
                else
                    %disp('inside')
                    b = [-a(:);  a(:)];
                    ind= [1:3,1:3]';
                    t = [q(:); q(:)];
                    [~,i] = min(abs(t(:)-b(:)));
                    q(ind(i))=b(i);
                end
                
            elseif (a(1)==a(2))&&(epsilon(2)~=epsilon(1))&&(epsilon(2)~=1) %if cylinder
                r=a(2);
                rc = sum(q(1:2).^2).^0.5;
                azimuth = atan2(q(2),q(1));
                xyinside = (rc<=r);
                zinside = (-a(3)<=q(3))&(q(3)<=a(3));
                % two options xyclamp or z clamp
                qxy(1) = r*cos(azimuth);
                qxy(2) = r*sin(azimuth);
                qxy(3) = q(3);
                qz=q(:);
                b = [-a(3);  a(3)];
                [~,i] = min(abs(q(3)-b(:)));
                qz(3) = b(i); % clamp in z
                
                if(xyinside)&&(zinside)
                    %disp('(xyinside)&&(zinside)')
                    d=[sum((qxy(:)-p(:)).^2).^0.5;sum((qz(:)-p(:)).^2).^0.5];
                    if(d(1)<d(2))
                        q=qxy(:);
                    else
                        q=qz(:);
                    end
                    
                elseif(xyinside)&&(~zinside)
                    %disp('clamp in z')
                    q=qz(:); % clamp in z
                elseif(~xyinside)&&(zinside)
                    %disp('clamp in xy')
                    q=qxy(:); % clamp in xy
                elseif(~xyinside)&&(~zinside)
                    %disp('clamp in xy and z ');
                    q(1:2) = qxy(1:2); % clamp in xy
                    q(3) = qz(3); % clamp in z
                    q = q(:);
                end
            elseif  (epsilon(1)==epsilon(2))&&(epsilon(2)==1) %if sphere or axis aligned ellipsoid
                qs = q./a(:);
                q = (qs/norm(qs)).*a(:);
            end
            
        end
        
        
        function [ps,normals]=closestPointsOnZAlignedSuperEllipsoid(p,params)
            % p is input query points.
            % p must be dim x n
            % returns closest pts on sphere and the corresponding normals
            xc =params.xc;
            a = params.a;
            epsilon = params.epsilon;
            n=size(p,2);
            for ind =1:n,
                q = p(:,ind)-xc(:); % convert to object frame with the origin at the geomertic center
                %====BOX
                if(epsilon(2)==epsilon(1))&&(epsilon(2)~=1) %if box
                    % if outside box.
                    inside=(-a(1)<=q(1))&(q(1)<=a(1))& (-a(2)<=q(2))&(q(2)<=a(2))& (-a(3)<=q(3))&(q(3)<=a(3));
                    if(~inside)
                        for j= 1:3,
                            vert=q(j);
                            b = [-a(j) a(j)];
                            vert = max(vert,min(b));
                            vert = min(vert,max(b));
                            q(j) =vert;
                        end
                    else
                        b = [-a(:);  a(:)];
                        k= [1:3,1:3]';
                        t = [q(:); q(:)];
                        [~,j] = min(abs(t(:)-b(:)));
                        q(k(j))=b(j);
                    end
                    %====CYLINDER
                elseif (a(1)==a(2))&&(epsilon(2)~=epsilon(1))&&(epsilon(2)~=1) %if cylinder
                    r=a(2);
                    rc = sum(q(1:2).^2).^0.5;
                    azimuth = atan2(q(2),q(1));
                    xyinside = (rc<=r);
                    zinside = (-a(3)<=q(3))&(q(3)<=a(3));
                    % two options xyclamp or z clamp
                    qxy(1) = r*cos(azimuth);
                    qxy(2) = r*sin(azimuth);
                    qxy(3) = q(3);
                    qz=q(:);
                    b = [-a(3);  a(3)];
                    [~,i] = min(abs(q(3)-b(:)));
                    qz(3) = b(i); % clamp in z
                    
                    if(xyinside)&&(zinside)
                        d=[sum((qxy(:)-q(:)).^2).^0.5;sum((qz(:)-q(:)).^2).^0.5];
                        if(d(1)<d(2))
                            q=qxy(:);
                        else
                            q=qz(:);
                        end
                    elseif(xyinside)&&(~zinside)
                        q=qz(:); % clamp in z
                    elseif(~xyinside)&&(zinside)
                        q=qxy(:); % clamp in xy
                    elseif(~xyinside)&&(~zinside)
                        q(1:2) = qxy(1:2); % clamp in xy
                        q(3) = qz(3); % clamp in z
                        q = q(:);
                    end
                    %====SPHERE
                elseif  (epsilon(1)==epsilon(2))&&(epsilon(2)==1) %if sphere or axis aligned ellipsoid
                    qs = q./a(:);
                    q = (qs/norm(qs)).*a(:);
                end
                ps(:,ind) = q+xc(:); % transform back to world frame
                %
                % get normals
                x = q(1); y = q(2); z = q(3);
                e_rat =  epsilon(1)/epsilon(2);
                temp = e_rat*(abs(x/a(1)).^(2/epsilon(1))+abs(y/a(2)).^(2/epsilon(1))).^(e_rat-1);
                dPhix =temp.*((2/epsilon(1))*(abs(x/a(1))).^((2/epsilon(1))-1)).*sign(x/a(1))*(1/a(1));
                dPhiy =temp.*((2/epsilon(1))*(abs(y/a(2))).^((2/epsilon(1))-1)).*sign(y/a(2))*(1/a(2));
                temp2 = e_rat*(abs(z/a(3)).^(2/epsilon(1))).^(e_rat-1);
                dPhiz =temp2.*((2/epsilon(1))*(abs(z/a(3))).^((2/epsilon(1))-1)).*sign(z/a(3))*(1/a(3));
                nnorm = (dPhix.^2+dPhiy.^2+dPhiz.^2).^0.5;
                nx=dPhix./nnorm;
                ny=dPhiy./nnorm;
                nz=dPhiz./nnorm;
                
                
                normals(:,ind)=[nx;ny;nz];
            end
        end
        
        function F = myObjFun(z,params)
            p = params.p;
            x = evalSuperEllipsoidPoint(z,params);
            F = ((x(1)-p(1))^2+(x(2)-p(2))^2+(x(3)-p(3))^2);
        end
        
        function x = evalSuperEllipsoidPoint(z,params)
            epsilon=params.epsilon;
            a=params.a;
            eta=z(1); % latitude - along the main dimension.
            w=z(2); % longitude
            %   etamax=pi/2;  etamin=-pi/2;
            %   wmax=pi;  wmin=-pi;
            
            % super ellipsoid x-axis form.
            % x(1) = a(1)* sign(sin(eta))* abs(sin(eta))^epsilon(2);
            % x(2) = a(2)* abs(cos(eta))^epsilon(2)* sign(sin(w))* abs(sin(w))^epsilon(1);
            %  x(3) = a(3)* abs(cos(eta))^epsilon(2)* sign(cos(w))* abs(cos(w))^epsilon(1);
            
            % super ellipsoid y-axis form.
            x(1) = a(1)* abs(cos(eta))^epsilon(2)* sign(sin(w))* abs(sin(w))^epsilon(1);
            x(2) = a(2)* sign(sin(eta))* abs(sin(eta))^epsilon(2);
            x(3) = a(3)* abs(cos(eta))^epsilon(2)* sign(cos(w))* abs(cos(w))^epsilon(1);
            
            % super ellipsoid z-axis form.
            %   x(1) = a(1)* abs(cos(eta))^epsilon(2)* sign(cos(w))* abs(cos(w))^epsilon(1);
            %   x(2) = a(2)* abs(cos(eta))^epsilon(2)* sign(sin(w))* abs(sin(w))^epsilon(1);
            %   x(3) = a(3)* sign(sin(eta))* abs(sin(eta))^epsilon(2);
        end
        function [ps,normals,y,dndx]=closestPointsOnSphere(p)
            % p is input query points.
            % p must be dim x n
            % returns closest pts on sphere and the corresponding normals
            
            xc = [0 0 0];
            R =  0.05;
            
            dim = size(p,1);
            nz =size(p,2);
            y = p-repmat(xc(:),1,nz); % defined in the sphere coordinate frame.
            norm_y = repmat(sum(y.^2,1).^0.5,dim,1); %y/norm(y)
            [~,col] = find(norm_y==0); % p is equal to xc ==> all points on the sphere are equidistant.
            norm_y(:,col)=1;
            ps= repmat(xc(:),1,nz)+R*(y./norm_y);
            if(~isempty(col))
                ps(1,unique(col))= ps(1,unique(col)) + R;
            end
            %n = [2*(ps-repmat(xc(:),1,nz))];
            % get unit normals and its derivative in cartesian space.
            
            dndx = zeros(dim*nz,dim);
            for i=1:nz,
                ni = 2.0*(p(:,i)-xc(:));
                dni=2.0*eye(dim);
                
                ni = 2.0*(ps(:,i)-xc(:)); % dpsdx does not seem to have much effect
                [~,dy] = normalize_v_dv(y(:,i),eye(dim));
                dpsdx = R*dy;
                dni=2.0*dpsdx;
                
                [ni,dni] = normalize_v_dv(ni,dni);
                normals(:,i)=ni;
                dndx(dim*(i-1)+1:dim*i,:)=dni;
            end
        end
        
        
        function [ps,normals,y,dndx]=closestPointsOnSphere2(p)
            % p is input query points.
            % p must be dim x n
            % returns closest pts on sphere and the corresponding normals
            
            xc = [0 0 1];
            R =  0.05;
            
            dim = size(p,1);
            nz =size(p,2);
            y = p-repmat(xc(:),1,nz); % defined in the sphere coordinate frame.
            
            %n = [2*(ps-repmat(xc(:),1,nz))];
            % get unit normals and its derivative in cartesian space.
            dndx = zeros(dim*nz,dim);
            for i=1:nz,
                d_mean = 1;
                p_norm = norm(y(:,i));
                lambda0  = (sqrt(d_mean*p_norm^2)-1)/d_mean;
                options = optimset('Display','off');
                lambda = fzero(@(x) myfun2(x,y(:,i)),lambda0,options);
                ps(:,i)  = xc(:)+R*((eye(3)+lambda*eye(3))\y(:,i));
                
                
                ni = 2.0*(p(:,i)-xc(:));
                dni=2.0*eye(dim);
                
                
                ni = 2.0*(ps(:,i)-xc(:));
                [~,dy] = normalize_v_dv(y(:,i),eye(dim));
                dpsdx = R*dy;
                dni=2.0*dpsdx;
                
                [ni,dni] = normalize_v_dv(ni,dni);
                normals(:,i)=ni;
                dndx(dim*(i-1)+1:dim*i,:)=dni;
            end
        end
        
        function val = epsabs(x)
            es=1e-10;
            val = ((x.^2+es^2).^0.5);
        end
        function val = epssign(x)
            es=1e-10;
            val = x./((x.^2+es^2).^0.5);
        end
        function val = epsdsign(x)
            es=1e-10;
            val = es^2./((x.^2+es^2).^1.5);
        end
        
        function F = myfun2(z,p)
            %M = D./((1+z*D).^2);
            %F = y'*V'*M*V*y-1;
            A = eye(3);
            B=inv(eye(size(A))+z*A);
            F = p'*B'*A*B*p-1;
        end
        
        %Derivate of g(x) = v(x)/norm(v(x)) w.r.t to x. Requires v(xi) and d/dx(v(xi))
        % takes in a unnormalized vector and its derivate and returns the
        % normalized unit vector and the derivate of the normalized unit
        % vector.
        function [v,dv] = normalize_v_dv(v,dv)
            norm_v = (dot(v,v)).^0.5;
            dv= (dv*norm_v-v*(1/norm_v)*v'*dv)/(norm_v^2);% quotient rule of n/norm_n
            v=v/norm_v;
        end
        
        function [W,dW] = getWrenchMatrix(p,J)
            % p is input query points.
            % p must be dim x n
            % n is normals at the contacts
            dim = size(p,1);
            nz =size(p,2);
            nq = size(J,2);% J is 3nzxnq;
            [~,normals,dp,dndx] =closestPointsOnSphere(p);
            W = zeros(6,nz);
            dW = zeros(6*nz,nq);
            for i=1:nz,
                y =dp(:,i); % relative pos from object center
                ni = normals(:,i);
                Si = XProdSkew3d(y);
                wi = [ni;Si*ni]; %6x1
                W(:,i) = wi;%6x1
                %dndq = dndx * dxdq;
                Ji=J(3*(i-1)+1:3*i,:);
                dndxi=dndx(3*(i-1)+1:3*i,:);% dndx is 3nzx3
                dni = dndxi*Ji; % J is 3nzxnq; dndx is 1x1 and dni = 3xnq
                Sni = XProdSkew3d(ni);
                dwi = [dni;Sni'*Ji+Si*dni]; %6xnq  - There is a problem here.
                dW(6*(i-1)+1:6*i,:)=dwi;
            end
        end
        
        function [S]=XProdSkew3d(v)
            % v must be 3x1
            S = [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
        end
    end

    function [xstar,zstar] = iterativeGraspSearch2(obj,x0,v)
        manip = obj.manip;
        nx = manip.getNumStates();
        nq = nx/2;
        %nz = manip.num_contacts*dim;% *dim is only required when considering friction forces
        nz = manip.num_contacts;
        z0 = zeros(nz,1);
        q0 = x0(1:nq);
        
        problem.x0 = [q0;z0];
        % problem.objective = @(q) 0; % feasibility problem
        problem.objective = @(q) myobj(q);
        problem.nonlcon = @(qz) mycon(qz);
        problem.solver = 'fmincon';
        
        acc = 5e-02; %sub-mm accuracy
        % problem.options=optimset('DerivativeCheck','on','GradConstr','on','Algorithm','interior-point','Display','iter','OutputFcn',@drawme,'TolX',1e-14,'TolFun',acc,'TolCon',acc,'MaxFunEvals',15000);
        % problem.options=optimset('GradConstr','on','Algorithm','interior-point','Display','iter','OutputFcn',@drawme,'TolX',1e-14,'TolFun',acc,'TolCon',acc,'MaxFunEvals',15000);
        problem.options=optimset( 'GradObj','on','GradConstr','on','Algorithm','interior-point','Display','iter','OutputFcn',@drawme,'TolX',1e-14,'TolFun',acc,'TolCon',acc,'MaxFunEvals',15000);
        
        
        %lb_z =  -1e6*ones(nz,1);
        %lb_z(dim:dim:end) = 0; % normal forces must be >=0
        lb_z =  zeros(nz,1);
        ub_z =  ones(nz,1);
        
        % force search to be close to starting position
        problem.lb = [obj.manip.joint_limit_min; lb_z];
        problem.ub = [obj.manip.joint_limit_max; ub_z];
        
        %problem.lb(2) = 0.0; % body z
        
        [qz_sol,~,exitflag] = fmincon(problem);
        success=(exitflag==1);
        xstar = [qz_sol(1:nq); zeros(nq,1)];
        zstar = qz_sol(nq+(1:nz));
        
        disp(zstar');
        if (~success)
            error('failed to find fixed point');
            
        end
        
        function stop=drawme(qz,optimValues,state)
            stop=false;
            v.draw(0,[qz(1:nq); zeros(nq,1)]);
            
        end
        
        function [c,ceq,GC,GCeq] = mycon(qz)
            q=qz(1:nq);
            z=qz(nq+(1:nz));
            
            [~,C,B,~,dC,~] = manip.manipulatorDynamics(q,zeros(nq,1));
            [phiC,JC] = manip.contactConstraints(q,[],@mycollisionDetect);
            [p,J,dJ] = manip.contactPositions(q);
            
            % ignore friction constraints for now
            %C(X) <= 0, Ceq(X) = 0   (nonlinear constraints)
            
            %c = [-phiC;-z;ones(nz,1)'*z-7];
            %GC=[[-JC'; zeros(nz,length(phiC))],[zeros(nq,length(phiC));-eye(nz,length(phiC))],[zeros(nq,1);ones(nz,1)]];
            
            c = [-phiC;-z-0.001];
            GC=[[-JC'; zeros(nz,length(phiC))],[zeros(nq,length(phiC));-eye(nz,length(phiC))]];
            
            %ceq = 0;
            %GCeq = zeros(nq+nz,1);
            %ceq  = [z-1]; % set z =1;
            %GCeq = [zeros(nz,nq),eye(nz)]'; % nq+nz x 1
            
            %ceq  = [z.*phiC]; % complementarity condition nzx1
            %GCeq = [repmat(z,1,nq).*JC, repmat(phiC,1,nz).*eye(nz)]'; % nq+nzxnz
            
            ceq  = [z'*phiC]; % complementarity condition 1x1
            GCeq = [z'*JC, phiC']'; % nq+nzx  1
            
            [W,dW] = getWrenchMatrix(p,J);
            %W is 6 x nz
            %dW is 6*nz x nq its stacked 6 xq matrices
            dWzdq =zeros(6,nq);
            for i=1:nz,
                dWi = dW(6*(i-1)+1:6*i,:); % 6xnq
                dWzdq = dWzdq + z(i)*dWi; % 6xnq
            end
            dWzdz = W;% 6 x nz
            
            %ceq = W*z; % 6 x1
            %GCeq = [dWzdq,dWzdz]';  % must be nq+nz x 6
            %g = [0 0 0 0 0 0]';
            
            % ceq  = [phiC; W*z];  % [1x1;6x1] = 7x1
            %GCeq = [[JC, zeros(nz)]',[dWzdq,dWzdz]']; % [nq+nzxnz,nq+nzx6]
            
            ceq  = [z'*phiC; W*z];  % [1x1;6x1] = 7x1
            GCeq = [[z'*JC, phiC']',[dWzdq,dWzdz]']; % [nq+nzx1,nq+nzx6]
            
            %ceq  = [z.*phiC; W*z];  % [nzx1;6x1] = nz+6x1
            %GCeq = [[repmat(z,1,nq).*JC, repmat(phiC,1,nz).*eye(nz)]',[dWzdq,dWzdz]']; % [nq+nzx1,nq+nzxnz]
            
        end
        
        function [f,df] = myobj(q)
            q=q(1:nq);
            %[cm,J] = obj.manip.model.getCOM(q);
            [phiC,JC] = manip.contactConstraints(q,[],@mycollisionDetect);
            f = phiC'*phiC;
            df = [2*phiC'*JC, zeros(nz,1)']';
        end
        
        
        function [pos,vel,normal,mu] = mycollisionDetect(contact_pos)
            % for each column of contact_pos, find the closest point in the world
            % geometry, and it's (absolute) position and velocity, (unit) surface
            % normal, and coefficent of friction.
            
            % for now, just implement a ground height at y=0
            n = size(contact_pos,2);
            pos = [contact_pos(1:2,:);zeros(1,n)+1];
            normal = [zeros(2,n); ones(1,n)];
            
            
            % find the closest point on the sphere or ellipsoid.
            [pos,normal] =closestPointsOnSphere(contact_pos);
            
            vel = zeros(3,n); % static world assumption (for now)
            mu = ones(1,n);
        end
        
        function [ps,normals,y,dndx]=closestPointsOnSphere(p)
            % p is input query points.
            % p must be dim x n
            % returns closest pts on sphere and the corresponding normals
            
            xc = [0 0 1];
            R =  0.05;
            
            dim = size(p,1);
            nz =size(p,2);
            y = p-repmat(xc(:),1,nz); % defined in the sphere coordinate frame.
            norm_y = repmat(sum(y.^2,1).^0.5,dim,1); %y/norm(y)
            [~,col] = find(norm_y==0); % p is equal to xc ==> all points on the sphere are equidistant.
            norm_y(:,col)=1;
            ps= repmat(xc(:),1,nz)+R*(y./norm_y);
            if(~isempty(col))
                ps(1,unique(col))= ps(1,unique(col)) + R;
            end
            %n = [2*(ps-repmat(xc(:),1,nz))];
            % get unit normals and its derivative in cartesian space.
            
            dndx = zeros(dim*nz,dim);
            for i=1:nz,
                ni = 2.0*(p(:,i)-xc(:));
                dni=2.0*eye(dim);
                
                ni = 2.0*(ps(:,i)-xc(:));
                [~,dy] = normalize_v_dv(y(:,i),eye(dim));
                dpsdx = R*dy;
                dni=2.0*dpsdx;
                
                [ni,dni] = normalize_v_dv(ni,dni);
                normals(:,i)=ni;
                dndx(dim*(i-1)+1:dim*i,:)=dni;
            end
        end
        
        %Derivate of g(x) = v(x)/norm(v(x)) w.r.t to x. Requires v(xi) and d/dx(v(xi))
        % takes in a unnormalized vector and its derivate and returns the
        % normalized unit vector and the derivate of the normalized unit
        % vector.
        function [v,dv] = normalize_v_dv(v,dv)
            norm_v = (dot(v,v)).^0.5;
            dv= (dv*norm_v-v*(1/norm_v)*v'*dv)/(norm_v^2);% quotient rule of n/norm_n
            v=v/norm_v;
        end
        
        function [W,dW] = getWrenchMatrix(p,J)
            % p is input query points.
            % p must be dim x n
            % n is normals at the contacts
            dim = size(p,1);
            nz =size(p,2);
            nq = size(J,2);% J is 3nzxnq;
            [~,normals,dp,dndx] =closestPointsOnSphere(p);
            W = zeros(6,nz);
            dW = zeros(6*nz,nq);
            for i=1:nz,
                y =dp(:,i); % relative pos from object center
                ni = normals(:,i);
                Si = XProdSkew3d(y);
                wi = [ni;Si*ni]; %6x1
                W(:,i) = wi;%6x1
                %dndq = dndx * dxdq;
                Ji=J(3*(i-1)+1:3*i,:);
                dndxi=dndx(3*(i-1)+1:3*i,:);% dndx is 3nzx3
                dni = dndxi*Ji; % J is 3nzxnq; dndx is 1x1 and dni = 3xnq
                Sni = XProdSkew3d(ni);
                dwi = [dni;Sni'*Ji+Si*dni]; %6xnq  - There is a problem here.
                dW(6*(i-1)+1:6*i,:)=dwi;
            end
        end
        
        function [S]=XProdSkew3d(v)
            % v must be 3x1
            S = [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
        end
    end

end

